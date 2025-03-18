//
//  FBSSystemService.h
//  TrollInject
//
//  Created by Eric on 2025/2/25.
//

#ifndef FBSSystemService_h
#define FBSSystemService_h

#import <objc/NSObject.h>
#import <mach/mach.h>

extern NSString const *FBSDebugOptionKeyStandardOutPath;
extern NSString const *FBSDebugOptionKeyStandardErrorPath;
extern NSString const *FBSDebugOptionKeyWaitForDebugger;
extern NSString const *FBSDebugOptionKeyDebugOnNextLaunch;
extern NSString const *FBSOpenApplicationOptionKeyDebuggingOptions;

typedef uint32_t FBSOpenApplicationErrorCode;
static const FBSOpenApplicationErrorCode FBSOpenApplicationErrorCodeNone = 0;


@interface FBSSystemService : NSObject

- (mach_port_t)createClientPort;
- (void)openApplication:(NSString *)bundleID options:(NSDictionary *)options clientPort:(mach_port_t)clientPort withResult:(void (^)(NSError *error))handler;

@end


#endif /* FBSSystemService_h */
