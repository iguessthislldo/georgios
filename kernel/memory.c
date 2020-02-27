/* ===========================================================================
 * System Wide Memory Management
 * ===========================================================================
 * Interface for Managing System Memory
 *
 * x86_32 Map of Physical Memory:
 * Address| Contents    |Memory Range | Symbols
 *    0-> +-------------+---------+---+-----------------------
 *        | Unused                | 0 |
 *        +-----------------------+---+
 *        | BIOS Area             |   |
 * 1MiB-> +-----------------------+---+ <-KERNEL_LOW_START
 *        | Kernel                | 1 |
 *        +-----------------------+   | <-KERNEL_LOW_END
 *        | Frame Stack           |   |
 *        +-----------------------+   | <-frame_stack_bottom
 *        | Available             |   |
 *        |                       |
 *        |        ...
 *
 */

#include <memory.h>

#include <library.h>
#include <platform.h> // FRAME_SIZE and FRAME_LEVELS
#include <kernel.h> // Location of the kernel
#include <print.h> // Debug

u1 memory_range_num = 0;

mem_t memory_total = 0;
mem_t memory_used = 0;
mem_t frame_stack_count = 0;
mem_t frame_stack_size = 0;

mem_t other_range_frame_count = 0;

void memory_range_add(mem_t start, mem_t size, Memory_Range_Use use) {
    if (memory_range_num < MEMORY_RANGE_MAX) {
        memory_map[memory_range_num].start = start;
        memory_map[memory_range_num].size = size;
        memory_map[memory_range_num].use = use;

        if (memory_range_num != kernel_range && use == FRAME_STACK_USE) {
            other_range_frame_count += size / FRAME_SIZE;
        }

        memory_range_num++;
    } else {
        PANIC("Attempted to add more memory ranges than allowed.")
    }
}

mem_t frame_stack_bottom;
mem_t frame_stack_top;
mem_t frame_stack_left;

void memory_init() {
    print_format("Start of kernel: {x}\n", KERNEL_HIGH_START);
    print_format("End of kernel: {x}\n", KERNEL_HIGH_END);
    print_string("Size of kernel is ");
    print_uint(KERNEL_SIZE);
    print_string(" B (");
    print_uint(KERNEL_SIZE >> 10);
    print_string(" KiB)\n");

    // Calculate Size of Frame Stack
    const mem_t space = ALIGN(memory_map[kernel_range].size, FRAME_SIZE) - KERNEL_SIZE;
    const mem_t other_size = other_range_frame_count * sizeof(void*);
    if (other_size > space) {
        PANIC("memory_init: \"other\" range size is larger than total space");
    }
    mem_t n = (space - other_size) / FRAME_SIZE;
    mem_t total_size;
    while (true) {
        frame_stack_count = n + other_range_frame_count;
        frame_stack_size = ALIGN(frame_stack_count * sizeof(void*), FRAME_SIZE);
        mem_t stack_and_frames_size = frame_stack_size + n * FRAME_SIZE;
        total_size =
            stack_and_frames_size + PADDING(stack_and_frames_size, FRAME_SIZE);

        if (total_size > space) {
            n--;
        } else {
            break;
        }
    }
    memory_total = n * FRAME_SIZE;
    frame_stack_top = frame_stack_bottom = KERNEL_HIGH_END + frame_stack_size;
    frame_stack_left = n;

    mem_t start_of_krange_frames =
        memory_map[kernel_range].start +
        memory_map[kernel_range].size -
        n * FRAME_SIZE;

    print_string("Usable Memory: ");
    print_uint(memory_total);
    print_string(" B (");
    print_uint(memory_total >> 20);
    print_string(" MiB)\n");
    print_format("  Made up of {d} {d} KiB Frames\n", frame_stack_count, FRAME_SIZE >> 10);
    print_format("frame_stack_bottom: {x}\n", frame_stack_bottom);
    print_format("start of krange_frames: {x}\n", start_of_krange_frames);

    for (mem_t i = 0; i < n; i++) {
        *((mem_t*)frame_stack_top) = start_of_krange_frames + i * FRAME_SIZE;
        //print_format("{d}: {x}\n", i, *((mem_t*)frame_stack_top));
        frame_stack_top -= sizeof(mem_t);
    }
}

bool pop_frame(mem_t * address) {
    if (frame_stack_left) {
        frame_stack_left--;
        mem_t * s = (mem_t*) frame_stack_top;
        *address = *(++s);
        frame_stack_top = (mem_t) s;
        return false;
    }
    return true;
}

void push_frame(mem_t address) {
    frame_stack_left++;
    *((mem_t*)frame_stack_top) = address;
    frame_stack_top -= sizeof(mem_t);
}
