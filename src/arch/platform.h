#ifndef PLATFORM_HEADER
#define PLATFORM_HEADER

#ifdef __i386__
#include "x86_32/platform.h"
#else
#error "Target Platform Must Be x86_32"
#endif

typedef enum platform_init_enum {
    PLATFORM_INIT_SUCCESS = 0,
    PLATFORM_INIT_FAILURE,
} platform_init_t;
platform_init_t platform_init();

#endif
