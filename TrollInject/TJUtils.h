//
//  TJUtils.h
//  TrollInject
//
//  Created by Eric on 2025/3/14.
//

#ifndef TJUtils_h
#define TJUtils_h

#import <mach/mach.h>
#import <Foundation/Foundation.h>

kern_return_t mach_vm_read_buffer(mach_port_name_t task,
                                  mach_vm_address_t target_address,
                                  mach_vm_size_t size,
                                  uint8_t *buffer,
                                  mach_vm_size_t *size_read);
extern
kern_return_t mach_vm_allocate
(
    vm_map_t target,
    mach_vm_address_t *address,
    mach_vm_size_t size,
    int flags
);

extern
kern_return_t mach_vm_read
(
    vm_map_read_t target_task,
    mach_vm_address_t address,
    mach_vm_size_t size,
    vm_offset_t *data,
    mach_msg_type_number_t *dataCnt
);

extern
kern_return_t mach_vm_write
(
    vm_map_t target_task,
    mach_vm_address_t address,
    vm_offset_t data,
    mach_msg_type_number_t dataCnt
);

extern
kern_return_t mach_vm_deallocate
(
    vm_map_t target,
    mach_vm_address_t address,
    mach_vm_size_t size
);

kern_return_t
mach_vm_read_string(mach_port_name_t task,
                    mach_vm_address_t target_address,
                    char **strout,
                    mach_vm_size_t max_bufsize,
                    mach_vm_size_t *size_read);

kern_return_t addRemoteEnvString(task_t task, mach_vm_address_t remoteKernelArgs, const char *envStr);
NSDictionary<NSString *, NSString *> *readRemoteEnvs(task_t task, mach_vm_address_t remoteKernelArgs);
kern_return_t swapRemoteEnvString(task_t task, mach_vm_address_t remoteKernelArgs, int index, const char *envStr, bool isStringLocal, mach_vm_address_t *oldEnvStr);
kern_return_t look_for_ptr_APIs(mach_vm_address_t *APIs);
kern_return_t read_APIs_SecurityFlags(vm_map_t task, mach_vm_address_t APIs,
                                      BOOL *allowAtPaths,
                                      BOOL *allowEnvVarsPrint,
                                      BOOL *allowEnvVarsPath,
                                      BOOL *allowEnvVarsSharedCache,
                                      BOOL *allowClassicFallbackPaths,
                                      BOOL *allowInsertFailures,
                                      BOOL *allowInterposing,
                                      BOOL *allowEmbeddedVars);

void launchWithWaitForDebugger(const char *bundleID);

mach_vm_address_t getMainExecutableBase(task_t task, mach_vm_address_t starter_sp);
mach_vm_address_t getLaunchSuspendedTaskSp(task_t task);

#endif /* TJUtils_h */
