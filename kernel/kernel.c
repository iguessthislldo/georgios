#include <library.h>
#include <print.h>
#include <platform.h>
#include <memory.h>

#include "kernel.h"

u1 process_count = 0;
u2 next_process_id = 1;

bool scheduler_enabled = true;
char * panic_message = 0;

void scheduler() {
    process_index = 0;
    thread_index = 0;
    while (true) {
        bool next_proc = false;
        if (scheduler_enabled && process_count) {
            process_t * p = &processes[process_index];
            if (p->thread_count) {
                thread_t * t = &p->threads[thread_index];
                if (t->valid) {
                    context_switch(&schedulerc, t->context);
                }
                thread_index = (thread_index + 1) % THREAD_COUNT_MAX;
                if (!thread_index) {
                    next_proc = true;
                }
            } else {
                next_proc = true;
            }
            if (next_proc) {
                process_index = (process_index + 1) % PROCESS_COUNT_MAX;
                thread_index = 0;
            }
        }
    }
}

extern mem_t setup_process(mem_t eip, mem_t esp);
extern void usermode();

void kernel_main() {

    memory_init();

    while (true) {
        asm("nop");
    }

    /*
    mem_t kernel_stack = 2 * FRAME_SIZE - 1;
    mem_t user_stack = FRAME_SIZE - 1;
    allocate_vmem(0, 3 * FRAME_SIZE);
    tss.esp0 = kernel_stack;

    memcpy(0, &&test_program_start, &&test_program_end - &&test_program_start);
    usermode(0, user_stack);

test_program_start:
    asm(
        "movl $99, %%eax\n\t" // print_char
        "movl $0x2B, %%ebx\n\t" // '+'
        "int $100\n\t"
        "movl $0, %%eax\n\t"
        "jmp * %%eax\n\t"
        ::: "%eax", "%ebx"
    );
test_program_end:
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

    print_string("Done\n");
}

