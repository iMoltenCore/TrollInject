//
//  TJExceptionServer.h
//  TrollInject
//
//  Created by Eric on 2025/3/6.
//

#ifndef TJExceptionServer_h
#define TJExceptionServer_h

#include <mach/mach.h>

typedef kern_return_t (*fn_exception_handler_t)(mach_port_t exception_port,
                                                mach_port_t thread_port,
                                                mach_port_t task_port,
                                                exception_type_t exception_type,
                                                mach_exception_data_t codes,
                                                mach_msg_type_number_t code_count);

mach_port_t
setup_exception_handler(task_t target_task, exception_mask_t mask, fn_exception_handler_t handler);

kern_return_t
detach_exception_handler(task_t target_task);

#endif /* TJExceptionServer_h */
