//
//  TJCourier.m
//  TrollInject
//
//  Created by Eric on 2025/3/7.
//

#import <Foundation/Foundation.h>

#import "TJCourier.h"
#import "TJUtils.h"
#import "TJExceptionServer.h"
#import "OSDependent.h"

const uint64_t LooseAMFIFlags_ = 0x6B;  // For debug mode, it's 0x17F

static dispatch_semaphore_t waiter_;
static mach_vm_address_t oldEnvStr_;
static mach_vm_address_t remoteKernelArgs_;

static
kern_return_t exc_handler(mach_port_t exception_port,
                          mach_port_t thread_port,
                          mach_port_t task_port,
                          exception_type_t exception_type,
                          mach_exception_data_t codes,
                          mach_msg_type_number_t code_count) {
    static int exception_counter_ = 0;
    // Get the thread state to inspect what happened
    arm_thread_state64_t thread_state;
    mach_msg_type_number_t state_count = ARM_THREAD_STATE64_COUNT;
    kern_return_t kr = thread_get_state(
        thread_port,
        ARM_THREAD_STATE64,
        (thread_state_t)&thread_state,
        &state_count
    );
    
    if (kr != KERN_SUCCESS) {
        NSLog(@"Failed to get thread state: %s", mach_error_string(kr));
        return KERN_FAILURE;
    }
    
    // Print some information about the exception
    NSLog(@"Exception at PC: 0x%llx", thread_state.__pc);
    
    if (exception_type == EXC_BAD_ACCESS) {
        NSLog(@"Bad memory access at address: 0x%llx", codes[1]);
        
        
        switch(thread_state.__pc & 0xFFF) {
        case (__DYLD_IN_DSC_OFFSET_STRLEN & 0xFFF):
            exception_counter_ ++;
            thread_state.__x[0] = oldEnvStr_;
            thread_state.__x[1] = oldEnvStr_ & (~0xF);
            break;
        case (__DYLD_IN_DSC_OFFSET_SIMPLE_GETENV & 0xFFF):
            thread_state.__x[8] = oldEnvStr_;
            thread_state.__x[10] = oldEnvStr_;
            if (exception_counter_ == 3) {
                exception_counter_ = 0;
                // 3rd time is the charm
                // dyld4::ProcessConfig::Security::getAMFI
                // First, look for this pointer
                mach_vm_size_t size_read;
                uint64_t remoteAMFIFlags;
                
                kr = mach_vm_read_buffer(task_port,
                                         thread_state.__sp + __DYLD_IN_DSC___DYLD_AMFI_FAKE___AMFIFLAGS_IN_SP,
                                         sizeof(uint64_t),
                                         (uint8_t *)&remoteAMFIFlags,
                                         &size_read);
                if (kr != KERN_SUCCESS) {
                    NSLog(@"[%d] mach_vm_read_buffer failed: %d", __LINE__, kr);
                    return KERN_FAILURE;
                }
                
                NSLog(@"remoteAMFIFlags: 0x%llx", remoteAMFIFlags);
                
                kr = mach_vm_write(task_port,
                                   thread_state.__sp + __DYLD_IN_DSC___DYLD_AMFI_FAKE___AMFIFLAGS_IN_SP,
                                   (vm_offset_t)&LooseAMFIFlags_,
                                   (mach_msg_type_number_t)sizeof(LooseAMFIFlags_));
                if (kr != KERN_SUCCESS) {
                    NSLog(@"[%d] mach_vm_write failed: %d", __LINE__, kr);
                    return KERN_FAILURE;
                }
                
                // Now we should restore the original env strings from glitched ones.
                kr = swapRemoteEnvString(task_port, remoteKernelArgs_, 0, (const char *)oldEnvStr_, NO, nil);
                if (kr != KERN_SUCCESS) {
                    NSLog(@"[%d] swapRemoteEnvString failed: %d", __LINE__, kr);
                    return KERN_FAILURE;
                }
                
                dispatch_async(dispatch_get_main_queue(), ^{
                    dispatch_semaphore_signal(waiter_);
                });
            }
            break;
        default:
            NSLog(@"Unknown exception location: 0x%llx", thread_state.__pc);
            abort();
        }
        
        // Set the modified thread state
        kr = thread_set_state(
            thread_port,
            ARM_THREAD_STATE64,
            (thread_state_t)&thread_state,
            state_count
        );
        
        if (kr != KERN_SUCCESS) {
            NSLog(@"Failed to set thread state: %s", mach_error_string(kr));
            return KERN_FAILURE;
        }
        
        NSLog(@"Modified PC to skip faulting instruction: new PC=0x%llx", thread_state.__pc);
        return KERN_SUCCESS;  // We handled the exception
    } else {
        NSLog(@"Exception type: %d code=%llx", exception_type, codes[0]);
        abort();    // Should NOT handle
    }
}

#define GLITCHED_STRING         0xDEAD0

kern_return_t
brutely_inject_dylib(mach_port_t task, 
                     mach_vm_address_t remoteKernelArgs,
                     const char *dylib_path) {
    kern_return_t kern;
    mach_port_t exception_port = MACH_PORT_NULL;
    NSString *envDYLD_INSERT_LIBRARIES = [NSString stringWithFormat:@"DYLD_INSERT_LIBRARIES=%s", dylib_path];
    
    exception_port = setup_exception_handler(task, EXC_MASK_BAD_ACCESS, exc_handler);
    
    if (exception_port == MACH_PORT_NULL) {
        NSLog(@"[%d] failed to setup exception handler", __LINE__);
        kern = KERN_FAILURE;
        goto __out;
    }
    
    remoteKernelArgs_ = remoteKernelArgs;
    
    kern = addRemoteEnvString(task, remoteKernelArgs, [envDYLD_INSERT_LIBRARIES UTF8String]);
    if (kern != KERN_SUCCESS) {
        NSLog(@"[%d] failed to add remote env string: %d", __LINE__, kern);
        goto __out;
    }
    
    kern = swapRemoteEnvString(task, remoteKernelArgs, 0, (const char *)GLITCHED_STRING, NO, &oldEnvStr_);
    if (kern != KERN_SUCCESS) {
        NSLog(@"[%d] failed to swap remote env string: %d", __LINE__, kern);
        goto __out;
    }
    
    waiter_ = dispatch_semaphore_create(0);
    
    kern = task_resume(task);
    if (kern != KERN_SUCCESS) {
        NSLog(@"[%d] task_resume failed: %d", __LINE__, kern);
        goto __out;
    }
    
    const uint64_t timeout_secs = 10;
    dispatch_time_t timeout =
        dispatch_time(DISPATCH_TIME_NOW, timeout_secs * NSEC_PER_SEC);
    long sw = dispatch_semaphore_wait(waiter_, timeout);
    if (sw != 0) {
        NSLog(@"timed out trying to inject.");
        kern = KERN_FAILURE;
        goto __out;
    }
    
    kern = detach_exception_handler(task);
    if (kern != KERN_SUCCESS) {
        NSLog(@"[%d] detach failed, the target process may behave weird %d", __LINE__, kern);
        goto __out;
    }
__out:
    if (exception_port != MACH_PORT_NULL)
        mach_port_deallocate(task, exception_port);
    return kern;
}
