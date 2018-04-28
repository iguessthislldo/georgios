#include <library.h>
#include <print.h>
#include <platform.h>
#include <memory.h>

#include "kernel.h"

Process parentp;
Process childp;

bool scheduler_enabled = true;
char * panic_message = 0;

void scheduler() {
    enable_interrupts();
    while (true) {
        if (scheduler_enabled) {
            if (currentp->id || !childp.running) {
                currentp = &parentp;
            } else {
                currentp = &childp;
            }
            context_switch(&schedulerc, currentp->context);
        }
    }
}

u4 x = 0;
lock_t xlock = UNLOCKED;

void child() {
    enable_interrupts();
    // Child's work
    while (true) {
        for (u4 i = 0; i < 0xFFF; i++) {
            asm("nop");
        }
        if (attempt_lock(&xlock)) continue;
        print_char('<');
        x = childp.id;
        for (u4 i = 0; i < 0xFFFF; i++) {
            if (x != childp.id) {
                PANIC("Lock Error");
            }
        }
        print_char('>');
        release_lock(&xlock);
        for (u4 i = 0; i < 0xFFFFF; i++) {
            asm("nop");
        }
    }
}

void parent() {
    enable_interrupts();
    // Parent's Work
    while (true) {
        for (u4 i = 0; i < 0xFFFFFF; i++) {
            asm("nop");
        }
        if (attempt_lock(&xlock)) continue;
        print_char('[');
        x = parentp.id;
        for (u4 i = 0; i < 0xFFFFF; i++) {
            if (x != parentp.id) {
                PANIC("Lock Error");
            }
        }
        print_char(']');
        childp.running = 1;
        release_lock(&xlock);
    }
}

extern void * setup_process(u4 eip, u4 esp);
extern void usermode();

void kernel_main() {

    memory_init();

    /*
    asm (
        "movl $66, %eax\n\t"
        "int $100\n\t"
    );
    */
    /*
    allocate_vmem(0, 2 * FRAME_SIZE);
    tss.esp0 = 2 * FRAME_SIZE - 1;
    */
    /*
    asm ("movb $0x90, (0)");  // nop
    asm ("movb $0xeb, (1)");  // jmp to prev instruction
    asm ("movb $0xfd, (2)");
    */
    /*
    asm ("movb $0xb8, (0)"); // mov $0x42,%eax
    asm ("movb $0x42, (1)");
    asm ("movb $0x00, (2)");
    asm ("movb $0x00, (3)");
    asm ("movb $0x00, (4)");
    asm ("movb $0xcd, (5)"); // int $0x64
    asm ("movb $0x64, (6)");
    breakpoint();
    usermode();
    */

    /*
    allocate_vmem(0, KiB(10));

    parentp.id = 0;
    parentp.running = 1;
    parentp.stack = KiB(5) - 1;
    parentp.context = setup_process((u4) parent, parentp.stack);

    childp.id = 1;
    childp.running = 0;
    childp.stack = KiB(10) - 1;
    childp.context = setup_process((u4) child, childp.stack);

    currentp = &parentp;
    scheduler();
    */
}

