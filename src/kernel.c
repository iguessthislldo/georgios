#include <library.h>
#include <print.h>
#include <platform.h>

#include "frame.h"

#define FRAME_LEVELS 12 // 4096 * 4KiB Frames = 16MiB
#define FRAMES 1 << FRAME_LEVELS
Frame_Context fctx;
u1 frame_info[FRAMES];

extern u4 start_of_kernel;
extern u4 end_of_kernel;

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

void page_directory_print(u4 index) {
    page_directory_t pd = page_directory_get(index);
    print_format("{d}: ", index);
    if (pd.present) {
        print_format("{x}\n", pd.address);
        print_format("    4 MiB Pages? {d}\n", pd.page_size);
        print_format("    Has been Accessed? {d}\n", pd.accessed);
        print_format("    Cache Disabled? {d}\n", pd.cache_disabled);
        print_format("    Write Through? {d}\n", pd.write_through);
        print_format("    User Accessible? {d}\n", pd.user);
        print_format("    Writable? {d}\n", pd.writable);
    } else {
        print_string("Not Present\n");
    }
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

    print_format("Start of kernel: {x}\n", &start_of_kernel);
    print_format("End of kernel: {x}\n", &end_of_kernel);

    fctx.max_level = FRAME_LEVELS;
    fctx.frame_count = FRAMES;
    fctx.frame_size = 4 * 1024; // 4 KiB
    fctx.frame_info = &frame_info[0];
    fctx.begin = &end_of_kernel;

    u4 * page_table = allocate_frames(fctx, 1);

    print_string("Kernel Done\n");
    halt();
}

