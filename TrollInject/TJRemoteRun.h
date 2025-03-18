//
//  TJRemoteRun.h
//  TrollInject
//
//  Created by Eric on 2025/3/4.
//

#ifndef TJRemoteRun_h
#define TJRemoteRun_h

#import <mach/mach.h>

kern_return_t RRcreate_thread(vm_map_t task, thread_act_t *pthreadnp);
/*
 * Note this can crash the app if it is running in a very initial state,
 * namely before dyld initialization. It's in conflict with
 * `task_restartable_ranges_register`.
 */
kern_return_t RRexecute_func(vm_map_t task,
                             thread_act_t thread,
                             mach_vm_address_t pc,
                             mach_vm_address_t *argv,
                             int argc,
                             uint64_t *retval);

#endif /* TJRemoteRun_h */
