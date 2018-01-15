#include <library.h>
#include <print.h>
#include <platform.h>

#include "frame.h"

extern u4 KERNEL_LOW_START;
extern u4 KERNEL_LOW_END;
extern u4 KERNEL_OFFSET;
extern u4 KERNEL_HIGH_START;
extern u4 KERNEL_HIGH_END;

#define TEST_RESULT(result)\
    print_string((result) ? "OK\n" : "FAILED\n");\
    if (!(result)) { return false; }

bool initialize() {
    bool r;

    // Platform
    r = platform_init();
    print_string("Initialized Platform... ");
    TEST_RESULT(r);

    return true;
}

// Bochs i386 32 MiB Usable Memory
// 0 -> 0x9f000 - 1
// 0x100000 -> 0x100000 + 0x1ef0000 - 1

void kernel_main() {
    if (!initialize()) {
        print_string("Kernel Failed to Initialize\n");
        halt();
    }
    print_string("Kernel Loaded\n");

    print_format("Start of kernel: {x}\n", &KERNEL_HIGH_START);
    print_format("End of kernel/Start of Heap: {x}\n", &KERNEL_HIGH_END);

    fctx.max_level = FRAME_LEVELS;
    fctx.frame_count = FRAMES;
    fctx.frame_size = 4 * 1024; // 4 KiB
    fctx.frame_info = &frame_info[0];
    fctx.begin = &KERNEL_HIGH_END;

    print_format("End of Heap: {x}\n", fctx.begin + fctx.frame_size * fctx.frame_count);

    print_string("Kernel Done\n");
    halt();
}

