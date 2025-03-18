//
//  TJUtils.m
//  TrollInject
//
//  Created by Eric on 2025/3/14.
//

#import <Foundation/Foundation.h>
#import "FBSSystemService.h"
#import <mach-o/dyld.h>
#import "TJUtils.h"
#import "OSDependent.h"

kern_return_t
mach_vm_read_buffer(mach_port_name_t task,
                    mach_vm_address_t target_address,
                    mach_vm_size_t size,
                    uint8_t *buffer,
                    mach_vm_size_t *size_read) {
    
    kern_return_t           kern;
    vm_offset_t             read_buf;
    mach_msg_type_number_t  cnt;
    kern = mach_vm_read(task, target_address, size, &read_buf, &cnt);
    if (kern != KERN_SUCCESS) {
        return kern;
    }
    
    assert(cnt <= size);
    
    memcpy(buffer, (const void *)read_buf, cnt);
    *size_read = cnt;
    
    assert(mach_vm_deallocate(mach_task_self(), read_buf, cnt) == KERN_SUCCESS);
    
    return kern;
}

/*
 * Free the strout with free()
 */
kern_return_t
mach_vm_read_string(mach_port_name_t task,
                    mach_vm_address_t target_address,
                    char **strout,
                    mach_vm_size_t max_bufsize,
                    mach_vm_size_t *size_read) {
    kern_return_t           kern;
    const mach_vm_size_t    BLOCK_SIZE = 0x40;
    char                    blockbuf[BLOCK_SIZE];
    mach_vm_size_t          cur_size = 0;
    mach_vm_size_t          single_size_read;
    mach_vm_size_t          string_lenth = -1;
    
    if (0 == max_bufsize) max_bufsize = 0x4000;   // Long enough
    *size_read = 0;
    while(cur_size < max_bufsize) {
        kern = mach_vm_read_buffer(task, target_address + cur_size, BLOCK_SIZE, (uint8_t *)&blockbuf[0], &single_size_read);
        if (kern != KERN_SUCCESS) return kern;
        
        // Look for 0.
        for (mach_vm_size_t i = 0; i < single_size_read; i ++) {
            if (blockbuf[i] == '\0') {
                string_lenth = cur_size + i;
                break;
            }
        }
        if (string_lenth != -1) break;
        cur_size += single_size_read;
    }
    if (string_lenth == -1) return KERN_INSUFFICIENT_BUFFER_SIZE;
    
    *strout = malloc(string_lenth + 1);
    return mach_vm_read_buffer(task, target_address, string_lenth + 1, (uint8_t *)*strout, size_read);
}

#define MAX_KERNEL_ARGS   128

// We even accept glitched strings
kern_return_t
swapRemoteEnvString(task_t task,
                    mach_vm_address_t remoteKernelArgs,
                    int index,
                    const char *envStr,
                    bool isStringLocal,
                    mach_vm_address_t *oldEnvStr) {
    kern_return_t           kern;
    mach_vm_size_t          size_read;
    mach_vm_address_t       remoteEnvStr;
    
    const char *kernelArgs[MAX_KERNEL_ARGS];
    kern = mach_vm_read_buffer(task, remoteKernelArgs + 0x10, sizeof(kernelArgs), (uint8_t *)&kernelArgs[0], &size_read);
    if (kern != KERN_SUCCESS) {
        NSLog(@"[%d] mach_vm_read_buffer failed: %d", __LINE__, kern);
        goto __failed;
    }
    
    // Find the 3rd zero.
    int zero_counter = 0;
    int i, zero_indices[3];
    for (i = 0; i < MAX_KERNEL_ARGS; i ++) {
        if (kernelArgs[i] == 0) {
            zero_indices[zero_counter] = i;
            ++ zero_counter;
            if (zero_counter == 3) break;
        }
    }
    
    if (zero_counter != 3 || i >= MAX_KERNEL_ARGS - 1) {
        NSLog(@"Too many kernel args...");
        kern = KERN_INSUFFICIENT_BUFFER_SIZE;
        goto __failed;
    }
    
    if (index >= zero_indices[1] - zero_indices[0]) {
        NSLog(@"Index out of env range...");
        kern = KERN_INVALID_ARGUMENT;
        goto __failed;
    }
    
    if (oldEnvStr)
        *oldEnvStr = (mach_vm_address_t)kernelArgs[zero_indices[0] + index + 1];
    
    if (isStringLocal) {
        // Allocate the string buffer remotely and write the string.
        size_t envStrlen = strlen(envStr);
        kern = mach_vm_allocate(task, &remoteEnvStr, envStrlen + 1, VM_FLAGS_ANYWHERE);
        if (kern != KERN_SUCCESS) {
            NSLog(@"[%d] mach_vm_allocated failed: %d", __LINE__, kern);
            goto __failed;
        }
        
        kern = mach_vm_write(task, remoteEnvStr, (vm_offset_t)envStr, (mach_msg_type_number_t)envStrlen + 1);
        if (kern != KERN_SUCCESS) {
            NSLog(@"[%d] mach_vm_write failed: %d", __LINE__, kern);
            goto __failed;
        }
    } else {
        // remote string, already exists, just go on.
        remoteEnvStr = (mach_vm_address_t)envStr;
    }
    
    kernelArgs[zero_indices[0] + index + 1] = (const char *)remoteEnvStr;
    // Write back
    kern = mach_vm_write(task,
                         remoteKernelArgs + 0x10,
                         (vm_offset_t)kernelArgs,
                         (mach_msg_type_number_t)sizeof(kernelArgs));
    if (kern != KERN_SUCCESS) {
        NSLog(@"[%d] mach_vm_write failed: %d", __LINE__, kern);
        goto __failed;
    }
    
    return KERN_SUCCESS;
__failed:
    return kern;
    
    
}

kern_return_t
addRemoteEnvString(task_t task, mach_vm_address_t remoteKernelArgs, const char *envStr) {
    kern_return_t           kern;
    mach_vm_size_t          size_read;
    mach_vm_address_t       remoteEnvStr;
    
    const char *kernelArgs[MAX_KERNEL_ARGS];
    
    kern = mach_vm_read_buffer(task, remoteKernelArgs + 0x10, sizeof(kernelArgs), (uint8_t *)&kernelArgs[0], &size_read);
    if (kern != KERN_SUCCESS) {
        NSLog(@"[%d] mach_vm_read_buffer failed: %d", __LINE__, kern);
        goto __failed;
    }
    
    // Find the 3rd zero.
    int zero_index = 0;
    int i, first_zero = 0;
    for (i = 0; i < MAX_KERNEL_ARGS; i ++) {
        if (kernelArgs[i] == 0) {
            ++ zero_index;
            if (zero_index == 1) first_zero = i;
            if (zero_index == 3) break;
        }
    }
    
    if (zero_index != 3 || i >= MAX_KERNEL_ARGS - 1) {
        NSLog(@"Too many kernel args...");
        kern = KERN_INSUFFICIENT_BUFFER_SIZE;
        goto __failed;
    }
    
    if ((mach_vm_address_t)envStr >= 0x100000000) {
        // Allocate the string buffer remotely and write the string.
        size_t envStrlen = strlen(envStr);
        kern = mach_vm_allocate(task, &remoteEnvStr, envStrlen + 1, VM_FLAGS_ANYWHERE);
        if (kern != KERN_SUCCESS) {
            NSLog(@"mach_vm_allocated failed: %d", kern);
            goto __failed;
        }
        
        kern = mach_vm_write(task, remoteEnvStr, (vm_offset_t)envStr, (mach_msg_type_number_t)envStrlen + 1);
        if (kern != KERN_SUCCESS) {
            NSLog(@"mach_vm_write failed: %d", kern);
            goto __failed;
        }
    } else {
        // Unless it's a glitched string
        remoteEnvStr = (mach_vm_address_t)envStr;
    }
    
    // Move the buffer one block away.
    memmove(&kernelArgs[first_zero + 2], &kernelArgs[first_zero + 1], (i - first_zero) * sizeof(const char *));
    kernelArgs[first_zero + 1] = (const char *)remoteEnvStr;
    
    // Write back
    kern = mach_vm_write(task,
                         remoteKernelArgs + 0x10,
                         (vm_offset_t)kernelArgs,
                         (mach_msg_type_number_t)sizeof(kernelArgs));
    if (kern != KERN_SUCCESS) {
        NSLog(@"mach_vm_write failed: %d", kern);
        goto __failed;
    }
    
    return KERN_SUCCESS;
__failed:
    return kern;
}

NSDictionary<NSString *, NSString *> *readRemoteEnvs(task_t task, mach_vm_address_t remoteKernelArgs) {
    NSMutableDictionary<NSString *, NSString *> *ret = [NSMutableDictionary dictionary];
    
    kern_return_t           kern;
    mach_vm_size_t          size_read;

    const char *remoteArgs[MAX_KERNEL_ARGS];
    
    kern = mach_vm_read_buffer(task, remoteKernelArgs + 0x10, sizeof(remoteArgs), (uint8_t *)&remoteArgs[0], &size_read);
    if (kern != KERN_SUCCESS) {
        NSLog(@"mach_vm_read_buffer failed: %d", kern);
        goto __failed;
    }
    int i;
    for (i = 0; i < MAX_KERNEL_ARGS; i ++) {
        if (remoteArgs[i] == 0) {
            i ++;
            break;
        }
    }
    if (i == MAX_KERNEL_ARGS) {
        NSLog(@"Too many argc...");
        goto __failed;
    }
    
    for (; i < MAX_KERNEL_ARGS; i ++) {
        if (remoteArgs[i] == 0) break;
        char *strout;
        kern = mach_vm_read_string(task, (mach_vm_address_t)remoteArgs[i], &strout, 0, &size_read);
        if (kern != KERN_SUCCESS) {
            NSLog(@"mach_vm_read_string failed: %d", kern);
            goto __failed;
        }
        
        NSString *stringEnv = [NSString stringWithUTF8String:strout];
        NSArray<NSString *> *parsed = [stringEnv componentsSeparatedByString:@"="];
        if (parsed.count != 2) {
            NSLog(@"Malformed env string");
            goto __failed;
        }
        ret[parsed[0]] = parsed[1];
        free(strout);
    }
    
    return ret;
__failed:
    return nil;
}

kern_return_t read_APIs_SecurityFlags(vm_map_t task,
                                      mach_vm_address_t APIs,
                                      BOOL *allowAtPaths,
                                      BOOL *allowEnvVarsPrint,
                                      BOOL *allowEnvVarsPath,
                                      BOOL *allowEnvVarsSharedCache,
                                      BOOL *allowClassicFallbackPaths,
                                      BOOL *allowInsertFailures,
                                      BOOL *allowInterposing,
                                      BOOL *allowEmbeddedVars) {
    kern_return_t kern = KERN_SUCCESS;
    mach_vm_size_t size_read;
    
    mach_vm_address_t ProcessConfig;
    uint8_t AMFIFlags[16];
    
    kern = mach_vm_read_buffer(task, APIs + __APIS_OFFSET_PROCESSCONFIG_PTR, sizeof(mach_vm_address_t), (uint8_t *)&ProcessConfig, &size_read);
    if (kern != KERN_SUCCESS) {
        NSLog(@"[%d] mach_vm_read_buffer failed: %d", __LINE__, kern);
        goto __out;
    }
    
    kern = mach_vm_read_buffer(task, ProcessConfig + __PROCESSCONFIG_OFFSET_SECURITY, sizeof(AMFIFlags), &AMFIFlags[0], &size_read);
    if (kern != KERN_SUCCESS) {
        NSLog(@"[%d] mach_vm_read_buffer failed: %d]", __LINE__, kern);
        goto __out;
    }
    
    *allowAtPaths               = AMFIFlags[1];
    *allowEnvVarsPrint          = AMFIFlags[2];
    *allowEnvVarsPath           = AMFIFlags[3];
    *allowEnvVarsSharedCache    = AMFIFlags[4];
    *allowClassicFallbackPaths  = AMFIFlags[5];
    *allowInsertFailures        = AMFIFlags[6];
    *allowInterposing           = AMFIFlags[7];
    *allowEmbeddedVars          = AMFIFlags[8];
    
    NSLog(@"%@", [NSString stringWithFormat:@"%d %d %d %d %d %d %d %d",
                           AMFIFlags[1], AMFIFlags[2], AMFIFlags[3], AMFIFlags[4],
                           AMFIFlags[5], AMFIFlags[6], AMFIFlags[7], AMFIFlags[8]]);
__out:
    return kern;
}

void launchWithWaitForDebugger(const char *bundleID) {
    NSString *stdio_path = nil;
    NSFileManager *file_manager = [NSFileManager defaultManager];
    const char *null_path = "/dev/null";
    stdio_path =
        [file_manager stringWithFileSystemRepresentation:null_path
                                                  length:strlen(null_path)];
    NSMutableDictionary *debug_options = [NSMutableDictionary dictionary];
    NSMutableDictionary *options = [NSMutableDictionary dictionary];

    [debug_options setObject:stdio_path
                      forKey:FBSDebugOptionKeyStandardOutPath];
    [debug_options setObject:stdio_path
                      forKey:FBSDebugOptionKeyStandardErrorPath];
    [debug_options setObject:[NSNumber numberWithBool:YES]
                      forKey:FBSDebugOptionKeyWaitForDebugger];
    //[debug_options setObject:[NSNumber numberWithBool:YES]
    //                  forKey:FBSDebugOptionKeyDebugOnNextLaunch];
    [options setObject:debug_options
                forKey:FBSOpenApplicationOptionKeyDebuggingOptions];
    
    FBSSystemService *system_service = [[FBSSystemService alloc] init];
    mach_port_t client_port = [system_service createClientPort];
    __block dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    __block FBSOpenApplicationErrorCode attach_error_code = FBSOpenApplicationErrorCodeNone;
    NSString *bundleIDNSStr = [NSString stringWithUTF8String:bundleID];
    
    [system_service openApplication:bundleIDNSStr
                            options:options
                         clientPort:client_port
                         withResult:^(NSError *error) {
                           // The system service will cleanup the client port we
                           // created for us.
                           if (error)
                             attach_error_code =
                                 (FBSOpenApplicationErrorCode)[error code];
                           dispatch_semaphore_signal(semaphore);
                         }];
    const uint32_t timeout_secs = 9;
    dispatch_time_t timeout =
        dispatch_time(DISPATCH_TIME_NOW, timeout_secs * NSEC_PER_SEC);
    long success = dispatch_semaphore_wait(semaphore, timeout) == 0;
    if (!success) {
        NSLog(@"timed out trying to launch %@.", bundleIDNSStr);
    }
}

kern_return_t look_for_ptr_APIs(mach_vm_address_t *APIs) {
    kern_return_t kern = KERN_SUCCESS;
    const struct load_command *lc = nil;
    *APIs = 0;
    
    // Find __DATA, __dyld4 section of local libdyld.dylib
    uint32_t image_count = _dyld_image_count();
    const struct mach_header *libdyld = nil;
    mach_vm_offset_t libdyld_slide = 0;
    for (uint32_t i = 0; i < image_count; i ++) {
        if (!strcmp(_dyld_get_image_name(i), "/usr/lib/system/libdyld.dylib")) {
            libdyld = _dyld_get_image_header(i);
            libdyld_slide = _dyld_get_image_vmaddr_slide(i);
            break;
        }
    }
    if (libdyld == nil) {
        kern = KERN_NOT_FOUND;
        goto __out;
    }
    
    lc = (const struct load_command *)((const uint8_t *)libdyld + sizeof(struct mach_header_64));
    for (uint32_t i = 0; i < libdyld->ncmds; i ++) {
        
        switch (lc->cmd) {
            case LC_SEGMENT_64: {
                const struct segment_command_64 *sc = (const struct segment_command_64 *)lc;
                if (strstr(sc->segname, "__DATA") == sc->segname) {
                    const struct section_64 *s = (const struct section_64 *)((uint8_t *)sc + sizeof(struct segment_command_64));
                    for (uint32_t j = 0; j < sc->nsects; j ++) {
                        if (!strcmp(s->sectname, "__dyld4")) {
                            *APIs = s->addr + libdyld_slide;
                            break;
                        }
                        s = (const struct section_64 *)((uint8_t *)s + sizeof(struct section_64));
                    }
                }
                break;
            }
            default:
                break;
        }
        if (*APIs != 0) return KERN_SUCCESS;
        
        lc = (const struct load_command *)((const uint8_t *)lc + lc->cmdsize);
    }
    
__out:
    return KERN_NOT_FOUND;
}

mach_vm_address_t getMainExecutableBase(task_t task, mach_vm_address_t starter_sp) {
    kern_return_t       kern;
    mach_vm_size_t      size_read;
    
    uint8_t             buf[16];
    
    kern = mach_vm_read_buffer(task, starter_sp, sizeof(buf), &buf[0], &size_read);
    if (kern != KERN_SUCCESS) {
        NSLog(@"mach_vm_read_buffer failed: %d", kern);
        return 0;
    }
    
    return *(mach_vm_address_t *)(&buf[0]);
}

mach_vm_address_t getLaunchSuspendedTaskSp(task_t task) {
    kern_return_t                   kern;
    thread_array_t                  thread_list = NULL;
    mach_msg_type_number_t          thread_list_count = 0;
    
    mach_msg_type_number_t          count = ARM_THREAD_STATE64_COUNT;
    arm_thread_state64_t            state;
    
    kern = task_threads(task, &thread_list, &thread_list_count);
    if (kern != KERN_SUCCESS) {
        NSLog(@"task_threads failed: %d", kern);
        goto __failed;
    }
    
    if (thread_list_count != 1) {
        NSLog(@"Thread count of a new spawn process must be exact 1 while it's %d.", thread_list_count);
        goto __failed;
    }
    
    kern = thread_get_state(thread_list[0], ARM_THREAD_STATE64,
                            (thread_state_t)&state, &count);
    if (kern != KERN_SUCCESS) {
        NSLog(@"thread_get_state failed: %d", kern);
        goto __failed;
    }
    
    return state.__sp;
    
__failed:
    return 0;
}
