#ifndef PLATFORM_HEADER
#define PLATFORM_HEADER

#include "x86/platform.h"

#ifndef PLATFORM_SUPPORTED
#error "Platform Not Supported"
#endif

void platform_init();

#endif
