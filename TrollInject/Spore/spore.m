//
//  spore.m
//  TrollInject
//
//  Created by Eric on 2025/2/25.
//

#import <Foundation/Foundation.h>
#import "../TPRO.h"
#import "../OSDependent.h"
#import "../TJUtils.h"

extern char ***_NSGetEnviron(void);

static void
eliminate_env_at(const char **envs, int env_count, int index) {
    assert( env_count >= 0 && index >= 0 );
    assert( index < env_count );
    if (env_count - 1 - index > 0)
        memmove(&envs[index], &envs[index + 1], sizeof(const char *) * (env_count - 1 - index));
    envs[env_count - 1] = nil;
}

void
cleanup_traces(void) {
    mach_vm_address_t ptrAPIs, APIs, ProcessConfig, Security, Process, PathOverrides;
    kern_return_t kern;
    
    os_thread_self_restrict_tpro_to_rw();
    // Find API and ProcessConfig, etc
    
    kern = look_for_ptr_APIs(&ptrAPIs);
    if (kern != KERN_SUCCESS) {
        NSLog(@"[Spore] look_for_ptr_APIs failed: %d", kern);
        abort();
    }
    
    APIs = *(mach_vm_address_t *)ptrAPIs;
    ProcessConfig = *(mach_vm_address_t *)(APIs + __APIS_OFFSET_PROCESSCONFIG_PTR);
    Security = ProcessConfig + __PROCESSCONFIG_OFFSET_SECURITY;
    Process = ProcessConfig + __PROCESSCONFIG_OFFSET_PROCESS;
    PathOverrides = ProcessConfig + __PROCESSCONFIG_OFFSET_PATHOVERRIDES;
    
    // Restore AMFI flags
    *(bool *)(Security + __SECURITY_OFFSET_ALLOWENVVARSPATH) = false;
    
    // Clear _insertedDylibs and _insertedDylibCount
    *(uint32_t *)(PathOverrides + __PATHOVERRIDES_OFFSET__INSERTEDDYLIBCOUNT) = 0;
    *(const char **)(PathOverrides + __PATHOVERRIDES_OFFSET__INSERTEDDYLIBS) = nil;
    
    // Clear env string
    
    const char **envs = *(const char ***)(Process + __PROCESS_OFFSET_ENVIRON);
    int i = 0, target_i = -1;
    const char *target_env = nil;
    
    while (1) {
        const char *env = envs[i ++];
        if (env == nil) break;
        if (!memcmp(env, "DYLD_INSERT_LIBRARIES=", 22)) {
            target_i = i - 1;
            target_env = env;
        }
    }
    
    if (target_i == -1) {
        NSLog(@"[Spore] DYLD_INSERT_LIBRARIES not found...");
    } else {
        NSLog(@"[Spore] Removing DYLD_INSERT_LIBRARIES at index %d", target_i);
        i --;   // Now i is the count
        eliminate_env_at(envs, i, target_i);
        // Also, at this time, the whole env string array has been copied out to somewhere else.
        eliminate_env_at((const char **)*_NSGetEnviron(), i, target_i);
        
        // Finally, deallocate the memory.
        mach_vm_deallocate(mach_task_self(), (mach_vm_address_t)target_env, PAGE_SIZE);
    }
    
    os_thread_self_restrict_tpro_to_ro();
}

__attribute__((constructor))
void
spore_init(void) {
    NSLog(@"[Spore] Im in.");
    cleanup_traces();
}
