#include <library.h>
#include <print.h>
#include <platform.h>
#include <memory.h>

#include "kernel.h"

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

    print_format("Start of kernel: {x}\n", &KERNEL_HIGH_START);
    print_format("End of kernel: {x}\n", &KERNEL_HIGH_END);
    print_string("Size of kernel is ");
    print_uint((mem_t) &KERNEL_SIZE);
    print_string(" B (");
    print_uint(((u4)&KERNEL_SIZE) >> 10);
    print_string(" KiB)\n");

    memory_init();

    print_string("Memory available to the kernel is ");
    print_uint(memory_total);
    print_string(" B (");
    print_uint(memory_total >> 20);
    print_format(" MiB)\n    Lost {d} bytes to the kernel and Frame Block System\n", lost_total);

    /*
    u4 i = 0;
    void * p;
    while ((p = allocate_frames(1))) {
        print_format("{d}\n", i++);
    }
    */

    /*
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
    */

    /*
    breakpoint();

    enable_interrupts();
    while (true) {}
    */
    /*
    scheduler();
    */
}

