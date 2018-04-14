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

u4 x = 0;
lock_t xlock = UNLOCKED;

void child() {
    enable_interrupts();
    // Child's work
    while (true) {
        while (attempt_lock(&xlock)) {
            for (u4 i = 0; i < 0x658; i++) {
                asm("nop");
            }
        }
        print_char('C');
        x = childp.id;
        for (u4 i = 0; i < 0xFFFF; i++) {
            if (x != childp.id) {
                print_char('~');
                halt();
            }
        }
        print_char('c');
        release_lock(&xlock);
        for (u4 i = 0; i < 0xFFFFF; i++) {
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
    enable_interrupts();
    
    // Parent's Work
    while (true) {
        while (attempt_lock(&xlock)) {
            for (u4 i = 0; i < 0x400; i++) {
                asm("nop");
            }
        }
        print_char('P');
        x = parentp.id;
        for (u4 i = 0; i < 0xFFFFF; i++) {
            if (x != parentp.id) {
                print_char('#');
                halt();
            }
        }
        print_char('p');
        release_lock(&xlock);
        for (u4 i = 0; i < 0xFFFFFF; i++) {
            asm("nop");
        }
    }
}

extern Context * setup_process(u4 eip, u4 esp);

void kernel_main() {

    breakpoint();

    u1 x = *((u1*)MiB(500));
    print_format("{d}\n", x);

    memory_init();

    extern mem_t temp_page_table[1024];
    mem_t * table_low = (mem_t *) (((mem_t) &temp_page_table[0]) - (mem_t) &KERNEL_OFFSET);
    page_directory[0] = ((mem_t) table_low) | 1;

    mem_t parent_page = pop_frame();
    temp_page_table[0] = parent_page | 1;

    mem_t child_page = pop_frame();
    temp_page_table[1] = child_page | 1;

    parentp.id = 0;
    parentp.running = 1;
    //parentp.stack = &KERNEL_HIGH_END + 0x3FFF;
    parentp.stack = 0xFFF;
    parentp.context = setup_process((u4) parent, parentp.stack);

    childp.id = 1;
    childp.running = 0;
    //childp.stack = &KERNEL_HIGH_END + 0x7FFF;
    childp.stack = 0x1FFF;
    childp.context = setup_process((u4) child, childp.stack);

    currentp = &parentp;
    scheduler();
}

