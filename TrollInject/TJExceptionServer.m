//
//  TJExceptionServer.m
//  TrollInject
//
//  Created by Eric on 2025/3/6.
//

#import <Foundation/Foundation.h>

#import "TJExceptionServer.h"
#import <pthread/pthread.h>
#import <mach/exception_types.h>

static void* exception_handler_thread(void* arg);

extern boolean_t mach_exc_server(
        mach_msg_header_t *InHeadP,
        mach_msg_header_t *OutHeadP);

// Structure to pass data to the exception handling thread
typedef struct {
    task_t target_task;
    mach_port_t exception_port;
} exception_handler_data_t;

static fn_exception_handler_t exc_handler_;

static struct {
    mach_msg_type_number_t count;
    exception_mask_t      masks[EXC_TYPES_COUNT];
    exception_handler_t   ports[EXC_TYPES_COUNT];
    exception_behavior_t  behaviors[EXC_TYPES_COUNT];
    thread_state_flavor_t flavors[EXC_TYPES_COUNT];
} old_exc_ports_;

kern_return_t
detach_exception_handler(task_t target_task) {
    kern_return_t kr = KERN_SUCCESS;
    for (mach_msg_type_number_t i = 0; i < old_exc_ports_.count; i++) {
        if (old_exc_ports_.ports[i] != MACH_PORT_NULL) {
            kr = task_set_exception_ports(
                                          target_task,
                                          old_exc_ports_.masks[i],
                                          old_exc_ports_.ports[i],
                                          old_exc_ports_.behaviors[i],
                                          old_exc_ports_.flavors[i]
            );
            
            if (kr != KERN_SUCCESS) {
                NSLog(@"Failed to restore exception port %d: %s",
                        i, mach_error_string(kr));
                break;
            }
            
            // Release our reference to the original port
            mach_port_deallocate(mach_task_self(), old_exc_ports_.ports[i]);
        }
    }
    
    exc_handler_ = nil;
    return kr;
}

mach_port_t
setup_exception_handler(task_t target_task, exception_mask_t mask, fn_exception_handler_t handler) {
    mach_port_t exception_port;
    kern_return_t kr;
    
    if (exc_handler_ != nil) {
        NSLog(@"setup_exception_handler has been called more than once. Currently only 1 task at a time is supported."
              "If you insist doing this, please call detach_exception_handler first at least.");
        return MACH_PORT_NULL;
    }
    
    // Create a port with receive rights to receive exception messages
    kr = mach_port_allocate(mach_task_self(), MACH_PORT_RIGHT_RECEIVE, &exception_port);
    if (kr != KERN_SUCCESS) {
        NSLog(@"Failed to allocate exception port: %s", mach_error_string(kr));
        return MACH_PORT_NULL;
    }
    
    // Add send rights so that the target task can send exception messages to this port
    kr = mach_port_insert_right(mach_task_self(), exception_port, exception_port, MACH_MSG_TYPE_MAKE_SEND);
    if (kr != KERN_SUCCESS) {
        NSLog(@"Failed to add send rights: %s", mach_error_string(kr));
        mach_port_deallocate(mach_task_self(), exception_port);
        return MACH_PORT_NULL;
    }
    
    kr = task_get_exception_ports(target_task, mask, old_exc_ports_.masks, &old_exc_ports_.count, old_exc_ports_.ports, old_exc_ports_.behaviors, old_exc_ports_.flavors);
    if (kr != KERN_SUCCESS) {
        NSLog(@"Failed to get old exception ports: %s", mach_error_string(kr));
        mach_port_deallocate(mach_task_self(), exception_port);
        return MACH_PORT_NULL;
    }
    
    // Set the exception port for the target task
    kr = task_set_exception_ports(
        target_task,                   // The task we're monitoring
        mask,                          // Which exceptions we want to catch
        exception_port,                // Our exception port
        EXCEPTION_DEFAULT | MACH_EXCEPTION_CODES,  // Behavior flags
        THREAD_STATE_NONE              // No specific thread state needed
    );
    
    if (kr != KERN_SUCCESS) {
        NSLog(@"Failed to set exception ports: %s", mach_error_string(kr));
        mach_port_deallocate(mach_task_self(), exception_port);
        return MACH_PORT_NULL;
    }
    
    exc_handler_ = handler;
    
    // Create a thread to handle exceptions
    pthread_t handler_thread;
    exception_handler_data_t *thread_data = malloc(sizeof(exception_handler_data_t));
    thread_data->target_task = target_task;
    thread_data->exception_port = exception_port;
    
    if (pthread_create(&handler_thread, nil, exception_handler_thread, thread_data) != 0) {
        NSLog(@"Failed to create exception handler thread");
        mach_port_deallocate(mach_task_self(), exception_port);
        free(thread_data);
        return MACH_PORT_NULL;
    }
    
    // Detach the thread so it can clean up itself when it exits
    pthread_detach(handler_thread);
    
    return exception_port;
}

typedef union MachMessageTag {
  mach_msg_header_t hdr;
  char data[1024];
} MachMessage;

// The exception handler thread function
static void* exception_handler_thread(void* arg) {
    exception_handler_data_t *data = (exception_handler_data_t *)arg;
    mach_port_t exception_port = data->exception_port;
    //task_t target_task = data->target_task;
    free(data);  // Free the thread data
    
    // Define the request and reply messages for the Mach exception handler
    MachMessage exc_msg;
    MachMessage reply_msg;
    
    while (1) {
        // Wait for an exception message
        kern_return_t kr = mach_msg(
            &exc_msg.hdr,               // Message buffer
            MACH_RCV_MSG | MACH_RCV_INTERRUPT,  // Option to receive a message
            0,                          // Send size (0 for receive)
            sizeof(exc_msg.data),       // Maximum receive size
            exception_port,             // Port to receive on
            MACH_MSG_TIMEOUT_NONE,      // No timeout
            MACH_PORT_NULL              // No notification port
        );
        
        if (kr != KERN_SUCCESS) {
            NSLog(@"Error receiving exception message: %s", mach_error_string(kr));
            break;
        }
        
        // Process the exception using MIG-generated functions
        // The actual exception handling happens in catch_mach_exception_raise
        // which is called by mach_exc_server
        boolean_t handled = mach_exc_server(&exc_msg.hdr, &reply_msg.hdr);
        
        if (!handled) {
            NSLog(@"Exception message not handled by mach_exc_server");
            continue;
        }
        
        // Send the reply
        kr = mach_msg(
            &reply_msg.hdr,                         // Message buffer
            MACH_SEND_MSG | MACH_SEND_INTERRUPT,    // Option to send a message
            reply_msg.hdr.msgh_size,                // Size of the message
            0,                          // Maximum receive size (0 for send)
            MACH_PORT_NULL,             // Destination port is in the header
            MACH_MSG_TIMEOUT_NONE,      // No timeout
            MACH_PORT_NULL              // No notification port
        );
        
        if (kr != KERN_SUCCESS) {
            NSLog(@"Error sending reply message: %s", mach_error_string(kr));
            break;
        }
    }
    
    return NULL;
}

kern_return_t catch_mach_exception_raise(
    mach_port_t exception_port,
    mach_port_t thread_port,
    mach_port_t task_port,
    exception_type_t exception_type,
    mach_exception_data_t codes,
    mach_msg_type_number_t code_count)
{
    NSLog(@"Exception caught: type=%d", exception_type);
    return exc_handler_(exception_port, thread_port, task_port, exception_type, codes, code_count);
}
