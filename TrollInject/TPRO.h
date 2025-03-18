//
//  TPRO.h
//  TrollInject
//
//  Created by Eric on 2025/3/13.
//

#ifndef TPRO_h
#define TPRO_h

#define _COMM_PAGE_START_ADDRESS        (0x0000000FFFFFC000ULL)
#define _COMM_PAGE_TPRO_WRITE_ENABLE    (_COMM_PAGE_START_ADDRESS + 0x0D0)
#define _COMM_PAGE_TPRO_WRITE_DISABLE   (_COMM_PAGE_START_ADDRESS + 0x0D8)

static inline bool os_thread_self_restrict_tpro_to_rw(void) {
    if (!*(uint64_t*)_COMM_PAGE_TPRO_WRITE_ENABLE) {
        // Doesn't have TPRO, skip this
        return false;
    }
    __asm__ __volatile__ (
        "mov x0, %0\n"
        "ldr x0, [x0]\n"
        "msr s3_6_c15_c1_5, x0\n"
        "isb sy\n"
        :: "r" (_COMM_PAGE_TPRO_WRITE_ENABLE)
       : "memory", "x0"
    );
    return true;
}

static inline bool os_thread_self_restrict_tpro_to_ro(void) {
    if (!*(uint64_t*)_COMM_PAGE_TPRO_WRITE_DISABLE) {
        // Doesn't have TPRO, skip this
        return false;
    }
    __asm__ __volatile__ (
        "mov x0, %0\n"
        "ldr x0, [x0]\n"
        "msr s3_6_c15_c1_5, x0\n"
        "isb sy\n"
        :: "r" (_COMM_PAGE_TPRO_WRITE_DISABLE)
       : "memory", "x0"
    );
    return true;
}

#endif /* TPRO_h */
