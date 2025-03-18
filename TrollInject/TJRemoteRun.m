//
//  TJRemoteRun.m
//  TrollInject
//
//  Created by Eric on 2025/3/4.
//

#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <pthread/pthread.h>
#import <sched.h>

#import "TJRemoteRun.h"
#import "TJUtils.h"

#define __PTHREADT_OFFSET_THREADID          0xd8

extern
kern_return_t mach_vm_allocate
(
    vm_map_t target,
    mach_vm_address_t *address,
    mach_vm_size_t size,
    int flags
);

extern
kern_return_t mach_vm_deallocate
(
    vm_map_t target,
    mach_vm_address_t address,
    mach_vm_size_t size
);

extern
kern_return_t mach_vm_write
(
    vm_map_t target_task,
    mach_vm_address_t address,
    vm_offset_t data,
    mach_msg_type_number_t dataCnt
);

extern int pthread_create_from_mach_thread(pthread_t * __restrict,
        const pthread_attr_t * _Nullable __restrict,
        void *(* _Nonnull)(void *), void * _Nullable __restrict);
extern int __bsdthread_terminate(void *freeaddr, size_t freesize, mach_port_t kport, mach_port_t joinsem);

// We use the fact that DYLD_SHARED_CACHE resides in the same address.
#define REMOTE_SYS_SYM(x)   (x)

static mach_vm_address_t 
find_retab(void) {
    return (mach_vm_address_t)REMOTE_SYS_SYM(mach_msg_overwrite) - 4;
}

kern_return_t RRcreate_thread(vm_map_t task, thread_act_t *pthreadnp) {
    kern_return_t kern;
    thread_act_t threadnp_proxy;
    mach_vm_address_t stack;
    mach_vm_size_t size_read;
    arm_thread_state64_t thread_state;
    uint64_t threadid_remote = 0;
    void *pthreadt_remote = nil;
    thread_act_t threadnp_remote = MACH_PORT_NULL;
    
    // 1. Create the thread.
    kern = thread_create(task, &threadnp_proxy);
    if (kern != KERN_SUCCESS) {
        NSLog(@"[%d] thread_create failed: %d", __LINE__, kern);
        return kern;
    }
    
    // 2. Set the thread state (Crucial and complex!).
    // Allocate the stack
    const uint64_t STACK_SIZE = 512 * 1024;
    kern = mach_vm_allocate(task, &stack, STACK_SIZE, VM_FLAGS_ANYWHERE);
    if (kern != KERN_SUCCESS) {
        NSLog(@"[%d] mach_vm_allocate stack failed: %s", __LINE__, mach_error_string(kern));
        goto __out;
    }
    
    thread_state.__sp   = stack + STACK_SIZE;
    thread_state.__sp   -= 32;                              // function usage
    thread_state.__x[0] = thread_state.__sp;                // pthread_t *
    thread_state.__x[1] = 0;                                // attributes
    thread_state.__x[2] = (uint64_t)REMOTE_SYS_SYM(sleep);  // func
    thread_state.__x[3] = 1000;                             // argument
    thread_state.__pc   = (uint64_t)REMOTE_SYS_SYM(pthread_create_from_mach_thread);
    
    // There maybe leakages to this. But you can blame Apple for lack of documentation.
    thread_state.__lr   = find_retab();
                            //(uint64_t)REMOTE_SYS_SYM(__bsdthread_terminate);

    // Set the initial instruction pointer
    mach_msg_type_number_t state_count = ARM_THREAD_STATE64_COUNT;
    kern = thread_set_state(threadnp_proxy, ARM_THREAD_STATE64, (thread_state_t)&thread_state, state_count);
    if (kern != KERN_SUCCESS) {
        NSLog(@"[%d] thread_set_state failed: %s", __LINE__, mach_error_string(kern));
        goto __out;
    }

    // 3. Resume the thread.
    kern = thread_resume(threadnp_proxy);
    if (kern != KERN_SUCCESS) {
        NSLog(@"[%d] thread_resume failed: %s", __LINE__, mach_error_string(kern));
        goto __out;
    }
    
    // 4. Now we read the pthread_t of the newly created thread
    while (pthreadt_remote == nil) {
        sched_yield();
        kern = mach_vm_read_buffer(task, stack + STACK_SIZE - 32,
                                   sizeof(void *), (uint8_t *)&pthreadt_remote,
                                   &size_read);
        if (kern != KERN_SUCCESS) {
            NSLog(@"[%d] mach_vm_read_buffer failed: %s", __LINE__, mach_error_string(kern));
            goto __out;
        }
    }
    
    while (threadid_remote == 0) {
        sched_yield();
        kern = mach_vm_read_buffer(task,
                                   (mach_vm_address_t)pthreadt_remote + __PTHREADT_OFFSET_THREADID,
                                   sizeof(uint64_t), (uint8_t *)&threadid_remote, &size_read);
        if (kern != KERN_SUCCESS) {
            NSLog(@"[%d] mach_vm_read_buffer failed: %s", __LINE__, mach_error_string(kern));
            goto __out;
        }
    }
    
    // 5. Remove the thread from the target
    kern = thread_suspend(threadnp_proxy);
    if (kern != KERN_SUCCESS) {
        NSLog(@"[%d] thread_suspend failed: %s", __LINE__, mach_error_string(kern));
        goto __out;
    }
    state_count = ARM_THREAD_STATE64_COUNT;
    kern = thread_get_state(threadnp_proxy, ARM_THREAD_STATE64, (thread_state_t)&thread_state, &state_count);
    if (kern != KERN_SUCCESS) {
        NSLog(@"[%d] thread_get_state failed: %s", __LINE__, mach_error_string(kern));
        goto __out;
    }
    
    thread_state.__x[0] = 0;
    thread_state.__x[1] = 0;
    thread_state.__x[2] = 0;
    thread_state.__x[3] = 0;
    thread_state.__pc = (uint64_t)REMOTE_SYS_SYM(__bsdthread_terminate);
    
    state_count = ARM_THREAD_STATE64_COUNT;
    kern = thread_set_state(threadnp_proxy, ARM_THREAD_STATE64, (thread_state_t)&thread_state, state_count);
    if (kern != KERN_SUCCESS) {
        NSLog(@"[%d] thread_set_state failed: %s", __LINE__, mach_error_string(kern));
        goto __out;
    }
    kern = thread_resume(threadnp_proxy);
    if (kern != KERN_SUCCESS) {
        NSLog(@"[%d] thread_resume failed: %s", __LINE__, mach_error_string(kern));
        goto __out;
    }
    
    mach_port_deallocate(mach_task_self(), threadnp_proxy);
    threadnp_proxy = MACH_PORT_NULL;
    
    // 6. Newly created thread id got, now we fetch mach port to it.
    
    thread_act_array_t threadList;
    mach_msg_type_number_t threadCount;
    mach_msg_type_number_t infocount;

    kern = task_threads(task, &threadList, &threadCount);
    if (kern != KERN_SUCCESS) {
        NSLog(@"[%d] task_threads failed: %s", __LINE__, mach_error_string(kern));
        goto __out;
    }
    int i;
    for (i = 0; i < threadCount; i++) {
        thread_identifier_info_data_t info;
        infocount = THREAD_IDENTIFIER_INFO_COUNT;
        
        kern = thread_info(threadList[i], THREAD_IDENTIFIER_INFO, (thread_info_t)&info, &infocount);
        if (kern != KERN_SUCCESS) {
            NSLog(@"[%d] thread_info failed: %s, but we are gonna go on", __LINE__, mach_error_string(kern));
        }
        
        if (info.thread_id == threadid_remote) break;
    }
    
    if (i < threadCount) threadnp_remote = threadList[i];
    // Deallocate the thread list
    for (int j = 0; j < threadCount; j++) {
        if (j != i) mach_port_deallocate(mach_task_self(), threadList[j]);
    }
    mach_vm_deallocate(mach_task_self(), (vm_address_t)threadList, sizeof(thread_act_t) * threadCount);
    if (i == threadCount) {
        NSLog(@"[%d] The working thread is not found!", __LINE__);
        kern = KERN_NOT_FOUND;
        goto __out;
    }
    
    // 7. Wait until the status is WAITING
    
    thread_basic_info_data_t basic_info;
    basic_info.run_state = TH_STATE_RUNNING;
    infocount = THREAD_BASIC_INFO_COUNT;
    
    while (basic_info.run_state != TH_STATE_WAITING) {
        kern = thread_info(threadnp_remote, THREAD_BASIC_INFO, (thread_info_t)&basic_info, &infocount);
        if (kern != KERN_SUCCESS) {
            NSLog(@"[%d] thread_info failed: %d", __LINE__, kern);
            goto __out;
        }
        sched_yield();
    }
    
    // 8. Now operation begins.
    kern = thread_suspend(threadnp_remote);
    if (kern != KERN_SUCCESS) {
        NSLog(@"[%d] thread_suspend failed: %d", __LINE__, kern);
        goto __out;
    }
    
    kern = thread_abort_safely(threadnp_remote);
    if (kern != KERN_SUCCESS) {
        NSLog(@"[%d] thread_abort_safely failed: %d", __LINE__, kern);
        goto __out;
    }
    
    mach_vm_address_t ret_addr = find_retab();
    state_count = ARM_THREAD_STATE64_COUNT;
    kern = thread_get_state(threadnp_remote, ARM_THREAD_STATE64,
                            (thread_state_t)&thread_state, &state_count);
    if (kern != KERN_SUCCESS) {
        NSLog(@"[%d] thread_get_state failed: %d", __LINE__, kern);
        goto __out;
    }
    
    thread_state.__lr = ret_addr;
    thread_state.__pc = ret_addr;
    state_count = ARM_THREAD_STATE64_COUNT;
    kern = thread_set_state(threadnp_remote, ARM_THREAD_STATE64,
                            (thread_state_t)&thread_state, state_count);
    if (kern != KERN_SUCCESS) {
        NSLog(@"[%d] thread_set_state failed: %d", __LINE__, kern);
        goto __out;
    }
    *pthreadnp = threadnp_remote;
    threadnp_remote = MACH_PORT_NULL;
__out:
    if (threadnp_remote != MACH_PORT_NULL)
        mach_port_deallocate(mach_task_self(), threadnp_remote);
    if (threadnp_proxy != MACH_PORT_NULL)
        mach_port_deallocate(mach_task_self(), threadnp_proxy);
    return kern;
}

kern_return_t RRexecute_func(vm_map_t task,
                             thread_act_t thread,
                             mach_vm_address_t pc,
                             mach_vm_address_t *argv, 
                             int argc,
                             uint64_t *retval) {
    // TODO: Sanity checks
    kern_return_t kern;
    mach_msg_type_number_t state_count = ARM_THREAD_STATE64_COUNT;
    arm_thread_state64_t thread_state;
    
    kern = thread_get_state(thread, ARM_THREAD_STATE64, (thread_state_t)&thread_state, &state_count);
    if (kern != KERN_SUCCESS) {
        NSLog(@"[%d] thread_get_state failed: %d", __LINE__, kern);
        goto __out;
    }
    
    for (int i = 0; i < argc; i ++) {
        if (i < 8) {
            thread_state.__x[i] = argv[i];
        } else {
            kern = mach_vm_write(task, thread_state.__sp + (i - 8) * sizeof(void *), (vm_offset_t)&argv[i], sizeof(mach_vm_address_t));
            if (kern != KERN_SUCCESS) {
                NSLog(@"[%d] mach_vm_write failed: %d", __LINE__, kern);
                goto __out;
            }
        }
    }
    
    thread_state.__pc = pc;
    thread_state.__lr = find_retab();
    
    state_count = ARM_THREAD_STATE64_COUNT;
    kern = thread_set_state(thread, ARM_THREAD_STATE64, (thread_state_t)&thread_state, state_count);
    if (kern != KERN_SUCCESS) {
        NSLog(@"[%d] thread_set_state failed: %d", __LINE__, kern);
        goto __out;
    }
    
    kern = thread_resume(thread);
    if (kern != KERN_SUCCESS) {
        NSLog(@"[%d] thread_resume failed: %d", __LINE__, kern);
        goto __out;
    }
    
    while (thread_state.__pc != find_retab()) {
        sched_yield();
        state_count = ARM_THREAD_STATE64_COUNT;
        kern = thread_get_state(thread, ARM_THREAD_STATE64, (thread_state_t)&thread_state, &state_count);
        if (kern != KERN_SUCCESS) {
            NSLog(@"[%d] thread_get_state failed: %d", __LINE__, kern);
            goto __out;
        }
    }
    
    kern = thread_suspend(thread);
    if (kern != KERN_SUCCESS) {
        NSLog(@"[%d] thread_suspend failed: %d", __LINE__, kern);
        goto __out;
    }
    
    *retval = thread_state.__x[0];
__out:
    return kern;
}
