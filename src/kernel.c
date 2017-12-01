#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __i386__
#include "x86_32/platform.h"
#else
#error "Target Platform Must Be x86_32"
#endif

#include "string.h"

void kernel_main(void) {
    platform_initialize();
    fb_print_string("Kernal Started\n\n");
    fb_print_string("Done\n");
}

