#ifndef PLATFORM_HEADER
#define PLATFORM_HEADER

#include "x86/platform.h"

#ifndef PLATFORM_SUPPORTED
#error "Platform Not Supported"
#endif

typedef enum platform_init_enum {
    PLATFORM_INIT_SUCCESS = 0,
    PLATFORM_INIT_FAILURE,
} platform_init_t;
bool platform_init();

#endif
