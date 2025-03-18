//
//  TJCourier.h
//  TrollInject
//
//  Created by Eric on 2025/3/7.
//

#ifndef TJCourier_h
#define TJCourier_h

#include <mach/mach.h>

/*
 * This function injects a dylib into a process that is at launch suspended state,
 * and resumes it, thus making the dylib run before anything else happens, except
 * that it is run after dyld initializations of course. Running before dyld is also
 * technically possible, but I don't think it's useful, for now. Also it's a lot of
 * work, so I didn't implement one.
 * Also, you cannot call it from the mainthread. Dispatch it.
 */
kern_return_t
brutely_inject_dylib(mach_port_t task,
                     mach_vm_address_t remoteKernelArgs,
                     const char *dylib_path);

#endif /* TJCourier_h */
