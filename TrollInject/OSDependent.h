//
//  OSDependent.h
//  TrollInject
//
//  Created by Eric on 2025/3/7.
//

#ifndef OSDependent_h
#define OSDependent_h

#define __APIS_OFFSET_PROCESSCONFIG_PTR             0x8
#define __PROCESSCONFIG_OFFSET_PROCESS              0x8
#define __PROCESSCONFIG_OFFSET_SECURITY             0xa8
#define __PROCESSCONFIG_OFFSET_PATHOVERRIDES        0x168
#define __PROCESS_OFFSET_ENVIRON                    0x70
#define __SECURITY_OFFSET_ALLOWENVVARSPATH          0x3
#define __PATHOVERRIDES_OFFSET__INSERTEDDYLIBS      0x60
#define __PATHOVERRIDES_OFFSET__INSERTEDDYLIBCOUNT  0x8c


#define __DYLD_IN_DSC_OFFSET_STRLEN                 0x1aa517b64
#define __DYLD_IN_DSC_OFFSET_SIMPLE_GETENV          0x1aa51e370

#define __DYLD_IN_DSC___DYLD_AMFI_FAKE___AMFIFLAGS_IN_SP    0x10
#define __DYLD_IN_DSC___DYLD_AMFI_FAKE___SECURITY_IN_SP     0x18

#endif /* OSDependent_h */
