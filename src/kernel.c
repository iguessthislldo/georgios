#include <library.h>
#include <print.h>
#include <platform.h>

#include "kernel.h"
#include "frame.h"

Process parentp;
Process childp;

void scheduler() {
    enable_interrupts();
    while (true) {
        disable_interrupts();
        print_format("S");
        if (currentp->id || !childp.running) {
            currentp = &parentp;
        } else {
            currentp = &childp;
        }
        enable_interrupts();
        context_switch(&schedulerc, currentp->context);
    }
}

void child() {
    // Child's work
    u4 x = 0;
    while (true) {
        disable_interrupts();
        print_char('~');
        enable_interrupts();
        x++;
        for (u4 i = 0; i < 0xFFFF; i++) {
            asm("nop");
        }
    }
}

void parent() {
    /*
    TODO: Start Child Here
    disable_interrupts();
    enable_interrupts();
    */
    childp.running = 1;
    
    // Parent's Work
    u4 x = 0;
    while (true) {
        disable_interrupts();
        print_char('#');
        enable_interrupts();
        x++;
        for (u4 i = 0; i < 0xFFFFF; i++) {
            asm("nop");
        }
    }
}

extern Context * setup_process(u4 eip, u4 esp);

void kernel_main() {
    print_string("Kernel Started\n");

    print_format("Start of kernel: {x}\n", &KERNEL_HIGH_START);
    print_format("End of kernel/Start of Heap: {x}\n", &KERNEL_HIGH_END);
    print_format("Offset: {x}\n", &KERNEL_OFFSET);
    print_format("FB: {x}\n", 0xB8000);
    print_format("Offset + FB: {x}\n", kernel_offset(0xB8000));

    fctx.max_level = FRAME_LEVELS;
    fctx.frame_count = FRAMES;
    fctx.frame_size = 4 * 1024; // 4 KiB
    fctx.frame_info = &frame_info[0];
    fctx.begin = &KERNEL_HIGH_END;

    print_format("End of Heap: {x}\n", fctx.begin + fctx.frame_size * fctx.frame_count);
    
    parentp.id = 0;
    parentp.running = 1;
    // parentp.stack = allocate_frames(fctx, 1) + fctx.frame_size - 1;
    parentp.stack = &KERNEL_HIGH_END + 0x3FFF;
    parentp.context = setup_process((u4) parent, parentp.stack);

    childp.id = 1;
    childp.running = 0;
    // childp.stack = allocate_frames(fctx, 1) + fctx.frame_size - 1;
    childp.stack = &KERNEL_HIGH_END + 0x7FFF;
    childp.context = setup_process((u4) child, childp.stack);

    currentp = &parentp;
    scheduler();

    /*
    breakpoint();

    enable_interrupts();
    while (true) {}
    */
    /*
    scheduler();
    */
}

