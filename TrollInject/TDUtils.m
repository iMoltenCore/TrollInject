#import "TDUtils.h"
#import "TJUtils.h"
#import "FBSSystemService.h"
#import "LSApplicationProxy+AltList.h"
#import "TJRemoteRun.h"
#import "TJExceptionServer.h"
#import "TJCourier.h"
#import "OSDependent.h"
#import <mach/mach.h>
#import <mach-o/loader.h>
#import <mach-o/dyld.h>
#import <dlfcn.h>
#import <TrollInject-Swift.h>

extern int pid_resume(int pid);

UIWindow *alertWindow_ = NULL;
UIWindow *kw_ = NULL;
UIViewController *root_ = NULL;
UIAlertController *alertController_ = NULL;
UIAlertController *doneController_ = NULL;
UIAlertController *errorController_ = NULL;

NSArray *appList(void) {
    NSMutableArray *apps = [NSMutableArray array];

    NSArray <LSApplicationProxy *> *installedApplications = [[LSApplicationWorkspace defaultWorkspace] atl_allInstalledApplications];
    [installedApplications enumerateObjectsUsingBlock:^(LSApplicationProxy *proxy, NSUInteger idx, BOOL *stop) {
        if (![proxy atl_isUserApplication]) return;

        NSString *bundleID = [proxy atl_bundleIdentifier];
        NSString *name = [proxy atl_nameToDisplay];
        NSString *version = [proxy atl_shortVersionString];
        NSString *executable = proxy.canonicalExecutablePath;
        NSURL *bundleURL = [proxy bundleURL];
        NSURL *dataContainerURL = [proxy dataContainerURL];
        NSURL *bundleContainerURL = [proxy bundleContainerURL];

        if (!bundleID || !name || !version || !executable) return;

        NSDictionary *item = @{
            @"bundleID":bundleID,
            @"name":name,
            @"version":version,
            @"executable":executable,
            @"bundleURL":bundleURL,
            @"dataContainerURL":dataContainerURL,
            @"bundleContainerURL":bundleContainerURL,
        };

        [apps addObject:item];
    }];

    NSSortDescriptor *descriptor = [[NSSortDescriptor alloc] initWithKey:@"name" ascending:YES selector:@selector(localizedCaseInsensitiveCompare:)];
    [apps sortUsingDescriptors:@[descriptor]];

    //[apps addObject:@{@"bundleID":@"", @"name":@"", @"version":@"", @"executable":@""}];

    return [apps copy];
}

NSUInteger iconFormat(void) {
    return (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) ? 8 : 10;
}

NSArray *sysctl_ps(void) {
    NSMutableArray *array = [[NSMutableArray alloc] init];

    int numberOfProcesses = proc_listpids(PROC_ALL_PIDS, 0, NULL, 0);
    pid_t pids[numberOfProcesses];
    bzero(pids, sizeof(pids));
    proc_listpids(PROC_ALL_PIDS, 0, pids, (int)sizeof(pids));
    for (int i = 0; i < numberOfProcesses; ++i) {
        if (pids[i] == 0) { continue; }
        char pathBuffer[PROC_PIDPATHINFO_MAXSIZE];
        bzero(pathBuffer, PROC_PIDPATHINFO_MAXSIZE);
        proc_pidpath(pids[i], pathBuffer, sizeof(pathBuffer));

        if (strlen(pathBuffer) > 0) {
            NSString *processID = [[NSString alloc] initWithFormat:@"%d", pids[i]];
            NSString *processName = [[NSString stringWithUTF8String:pathBuffer] lastPathComponent];
            NSDictionary *dict = [[NSDictionary alloc] initWithObjects:[NSArray arrayWithObjects:processID, processName, nil] forKeys:[NSArray arrayWithObjects:@"pid", @"proc_name", nil]];
            
            [array addObject:dict];
        }
    }

    return [array copy];
}

kern_return_t resumePid (pid_t pid)
{
    kern_return_t ret = 0;

    task_t task;

    ret = task_for_pid(mach_task_self(), pid, &task);
    if (ret != KERN_SUCCESS) {
        NSLog(@"task_for_pid failed: %s", mach_error_string(ret));
        return ret;
    }

    thread_act_array_t threadList;
    mach_msg_type_number_t threadCount;

    ret = task_threads(task, &threadList, &threadCount);
    if (ret != KERN_SUCCESS) {
        NSLog(@"task_threads failed: %s", mach_error_string(ret));
        return ret;
    }

    for (int i = 0; i < threadCount; i++) {
        thread_act_t thread = threadList[i];

        ret = thread_resume(thread);

        if (ret != KERN_SUCCESS) {
            NSLog(@"thread_resume failed: %s", mach_error_string(ret));
        }
    }

    // Deallocate the thread list
    for (int i = 0; i < threadCount; i++) {
        mach_port_deallocate(mach_task_self(), threadList[i]);
    }

    vm_deallocate(mach_task_self(), (vm_address_t)threadList, sizeof(thread_act_t) * threadCount);
    mach_port_deallocate(mach_task_self(), task);

    return ret;
}

void messageBoxDispatched(NSString *title, NSString *message) {
    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){
        [kw_ removeFromSuperview];
        kw_.hidden = YES;
    }];
    [alertController addAction:okAction];
    [root_ presentViewController:alertController animated:YES completion:nil];
}

void messageBox(NSString *title, NSString *message) {
    dispatch_async(dispatch_get_main_queue(), ^{
        messageBoxDispatched(title, message);
    });
}

void blockUI(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        alertWindow_ = [[UIWindow alloc] initWithFrame: [UIScreen mainScreen].bounds];
        alertWindow_.rootViewController = [UIViewController new];
        alertWindow_.windowLevel = UIWindowLevelAlert + 1;
        [alertWindow_ makeKeyAndVisible];
        
        // block the UI
            
        kw_ = alertWindow_;
        if([kw_ respondsToSelector:@selector(topmostPresentedViewController)])
            root_ = [kw_ performSelector:@selector(topmostPresentedViewController)];
        else
            root_ = [kw_ rootViewController];
    });
}

void UnblockUI(NSString *title, NSString *message) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (message) {
            messageBoxDispatched(title, message);
        } else {
            [kw_ removeFromSuperview];
            kw_.hidden = YES;
        }
    });
}

#define LAUNCH_FLAGS_NO_LAUNCH              0
#define LAUNCH_FLAGS_LAUNCH                 (1 << 0)
#define LAUNCH_FLAGS_SUSPENDED              (1 << 1)
#define LAUNCH_FLAGS_KILL_BEFORE_LAUNCH     (1 << 2)

void launchAndOperate(NSDictionary *app,
                      uint32_t launchFlags,
                      void (^operate)(task_t task, NSString **title, NSString **message)) {
    blockUI();
    NSLog(@"[TrollInject] spawning thread to operate in background...");
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSLog(@"[TrollInject] inside operating thread.");
        
        NSString *bundleID = app[@"bundleID"];
        NSString *name = app[@"name"];
        NSString *version = app[@"version"];
        NSString *executable = app[@"executable"];
        NSString *binaryName = [executable lastPathComponent];

        NSLog(@"[TrollInject] bundleID: %@", bundleID);
        NSLog(@"[TrollInject] name: %@", name);
        NSLog(@"[TrollInject] version: %@", version);
        NSLog(@"[TrollInject] executable: %@", executable);
        NSLog(@"[TrollInject] binaryName: %@", binaryName);
        
        pid_t pid = -1;
        NSArray *processes = nil;
        
        if ((launchFlags & LAUNCH_FLAGS_LAUNCH) != 0) {
            if ((launchFlags & LAUNCH_FLAGS_KILL_BEFORE_LAUNCH) != 0) {
                processes = sysctl_ps();
                NSLog(@"Before kill ===");
                for (NSDictionary *process in processes) {
                    NSString *proc_name = process[@"proc_name"];
                    if ([proc_name isEqualToString:binaryName]) {
                        pid = [process[@"pid"] intValue];
                        NSLog(@"before kill pid: found: %d", pid);
                    }
                }
                NSLog(@"Before kill end ===");
                
                if (pid != -1) {
                    kill(pid, SIGTERM);
                }
            }
            
            processes = sysctl_ps();
            for (NSDictionary *process in processes) {
                NSString *proc_name = process[@"proc_name"];
                if ([proc_name isEqualToString:binaryName]) {
                    pid = [process[@"pid"] intValue];
                    NSLog(@"after kill pid: found: %d, fail out", pid);
                    
                    UnblockUI(@"Caution", [NSString stringWithFormat:@"Cannot kill existing process: %d. Probably too slow to respond for the target, wait a sec and try again.", pid]);
                    return;
                }
            }
            
            if ((launchFlags & LAUNCH_FLAGS_SUSPENDED) != 0)
                launchWithWaitForDebugger([bundleID UTF8String]);
            else
                [[UIApplication sharedApplication] launchApplicationWithIdentifier:bundleID suspended:NO];
            
            sleep(1);
        }

        processes = sysctl_ps();
        for (NSDictionary *process in processes) {
            NSString *proc_name = process[@"proc_name"];
            if ([proc_name isEqualToString:binaryName]) {
                pid = [process[@"pid"] intValue];
                NSLog(@"after launch pid: found: %d", pid);
            }
        }

        if (pid == -1) {
            UnblockUI(@"Caution", [NSString stringWithFormat:@"Failed to locate a running %@", bundleID]);
            return;
        }
        
        task_t task;
        if (task_for_pid(mach_task_self(), pid, &task) != KERN_SUCCESS) {
            UnblockUI(@"Caution", @"task_for_pid failed");
            return;
        }
        
        NSString *title = nil, *message = nil;
        operate(task, &title, &message);
        UnblockUI(title, message);
    });
}


void peekStartupInfo(NSDictionary *app) {
    launchAndOperate(app,
                     LAUNCH_FLAGS_LAUNCH | LAUNCH_FLAGS_SUSPENDED | LAUNCH_FLAGS_KILL_BEFORE_LAUNCH,
                     ^(task_t task, NSString **title, NSString **message) {
        mach_vm_address_t sp = getLaunchSuspendedTaskSp(task);
        NSDictionary<NSString *, NSString *> *envs = readRemoteEnvs(task, sp);
        NSLog(@"envs: %@", [envs debugDescription]);
        
        mach_vm_address_t mainExecutableBase = getMainExecutableBase(task, sp);
        NSLog(@"mainExecutableBase: %llx", mainExecutableBase);
        
        task_resume(task);
        
        *title = @"Info";
        *message = [NSString stringWithFormat:@"mainExecutableBase: 0x%llx\nenvs: %@\n", mainExecutableBase, envs];
    });
}

void peekInfo(NSDictionary *app) {
    launchAndOperate(app,
                     LAUNCH_FLAGS_NO_LAUNCH, ^(task_t task, NSString **title, NSString **message) {
        BOOL allowAtPaths, allowEnvVarsPrint, allowEnvVarsPath, allowEnvVarsSharedCache;
        BOOL allowClassicFallbackPaths, allowInsertFailures, allowInterposing, allowEmbeddedVars;
        
        mach_vm_address_t ptrAPIs, remoteAPIs;
        mach_vm_size_t size_read;
        kern_return_t kern = look_for_ptr_APIs(&ptrAPIs);
        kern = mach_vm_read_buffer(task, ptrAPIs, sizeof(mach_vm_address_t), (uint8_t *)&remoteAPIs, &size_read);
        if (kern != KERN_SUCCESS) {
            *title = @"Error";
            *message = [NSString stringWithFormat:@"[%d] mach_vm_read_buffer failed: %d", __LINE__, kern];
            return;
        }
        kern = read_APIs_SecurityFlags(task, remoteAPIs,
                                       &allowAtPaths, &allowEnvVarsPrint,
                                       &allowEnvVarsPath, &allowEnvVarsSharedCache,
                                       &allowClassicFallbackPaths, &allowInsertFailures,
                                       &allowInterposing, &allowEmbeddedVars);
        if (kern != KERN_SUCCESS) {
            *title = @"Error";
            *message = [NSString stringWithFormat:@"Cannot read security"];
            return;
        }
        
        *title = @"Info";
        *message = [NSString stringWithFormat:@"allowAtPaths %d\n"
                                               "allowEnvVarsPrint %d\n"
                                               "allowEnvVarsPath %d\n"
                                               "allowEnvVarsSharedCache %d\n"
                                               "allowClassicFallbackPaths %d\n"
                                               "allowInsertFailures %d\n"
                                               "allowInterposing %d\n"
                                               "allowEmbeddedVars %d\n",
                                                allowAtPaths, allowEnvVarsPrint,
                                                allowEnvVarsPath, allowEnvVarsSharedCache,
                                                allowClassicFallbackPaths, allowInsertFailures,
                                                allowInterposing, allowEmbeddedVars];
    });
}

void launchWithDylib(NSDictionary *app) {
    launchAndOperate(app, LAUNCH_FLAGS_LAUNCH | LAUNCH_FLAGS_KILL_BEFORE_LAUNCH | LAUNCH_FLAGS_SUSPENDED, ^(task_t task, NSString **title, NSString **message) {
        mach_vm_address_t sp = getLaunchSuspendedTaskSp(task);

        NSString *spore = [[[NSBundle mainBundle] bundlePath] stringByAppendingPathComponent:@"libSecure.dylib"];
        NSArray<NSURL *> *targets = [NSArray arrayWithObject:[NSURL fileURLWithPath:spore]];
        NSArray<NSURL *> *copiedTargets = [Greeter copyAndSignDylib:app[@"bundleURL"] target:targets];
        if (copiedTargets.count != 1) {
            *title = @"Error";
            *message = @"copy failed..?";
            return;
        }
        
        kern_return_t kern = brutely_inject_dylib(task, sp, [[[copiedTargets firstObject] path] UTF8String]);
        if (kern != KERN_SUCCESS) {
            *title = @"Error";
            *message = [NSString stringWithFormat:@"[%d] brutely_inject_dylib failed: %d", __LINE__, kern];
            return;
        }
    });
}

void injectRunningWithDylib(NSDictionary *app) {
    launchAndOperate(app, LAUNCH_FLAGS_NO_LAUNCH, ^(task_t task, NSString **title, NSString **message) {
        thread_act_t working_threadnp;
        mach_vm_address_t dylibpath_remote;
        uint64_t retval;
        
        NSString *spore = [[[NSBundle mainBundle] bundlePath] stringByAppendingPathComponent:@"libSecure.dylib"];
        NSArray<NSURL *> *targets = [NSArray arrayWithObject:[NSURL fileURLWithPath:spore]];
        NSArray<NSURL *> *copiedTargets = [Greeter copyAndSignDylib:app[@"bundleURL"] target:targets];
        if (copiedTargets.count != 1) {
            *title = @"Error";
            *message = @"copy failed..?";
            return;
        }
        
        kern_return_t kern = RRcreate_thread(task, &working_threadnp);
        NSLog(@"RRcreate_thread: %d", kern);
        
        kern = mach_vm_allocate(task, &dylibpath_remote,
                                [[[copiedTargets firstObject] path] length] + 1, VM_FLAGS_ANYWHERE);
        if (kern != KERN_SUCCESS) {
            *title = @"Error";
            *message = [NSString stringWithFormat:@"[%d] mach_vm_allocate failed: %d", __LINE__, kern];
            return;
        }
        
        kern = mach_vm_write(task, dylibpath_remote,
                             (vm_offset_t)[[[copiedTargets firstObject] path] UTF8String],
                             (mach_msg_type_number_t)[[[copiedTargets firstObject] path] length] + 1);
        if (kern != KERN_SUCCESS) {
            *title = @"Error";
            *message = [NSString stringWithFormat:@"[%d] mach_vm_write failed: %d", __LINE__, kern];
            return;
        }
        
        mach_vm_address_t args[] = {
            dylibpath_remote,
            RTLD_LAZY
        };
        kern = RRexecute_func(task, working_threadnp, (mach_vm_address_t)dlopen, &args[0], 2, &retval);
        NSLog(@"RRcreate_from: %d", kern);
        if (kern == KERN_SUCCESS) {
            NSLog(@"dlopen returned: 0x%llx", retval);
        }
        
        *title = @"OK";
        *message = @"Switch to that App to see spore grow";
    });
}

NSString *trollDecryptVersion(void) {
    return [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleVersion"];
}
