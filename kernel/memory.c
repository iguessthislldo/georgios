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

lock_t memory_lock = UNLOCKED; // Lock that must be acquired to use the interface

/*
 * For x86_32
 *     FRAME_SIZE is 4096
 *     FRAME_LEVELS is 7
 *     1<<7 = 128 Frames per Frame Block
 *     128 * 4096 = 524288 B (1/2 MiB per Frame Block)
 */
#define FRAMES (1 << FRAME_LEVELS)
#define FRAME_BLOCK_SIZE (FRAMES * FRAME_SIZE)

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

/* ===========================================================================
 * Frame Allocation
 * ===========================================================================
 * Allocate Frames of Physical Memory in groups called Frame Blocks.
 * Frame Blocks use Buddy System allocation to allocate frames.
 *
 * ---------------------------------------------------------------------------
 * Buddy System
 * ---------------------------------------------------------------------------
 * In Frames Blocks, they are encoded as an array of bytes, each representing
 * a Frame. If the Least Significant Bit is set, the frame is being used. The
 * rest of the bits represent the level.
 *
 * Example:
 * Lvl Size Index: 0 1 2 3 4 5 6 7 8 9 A B C D E F
 * 0   16          0 . . . . . . . . . . . . . . .
 * 1   8           1 . . . . . . . 1 . . . . . . .
 * 2   4           2 . . . 2 . . . 2 . . . 2 . . .
 * 3   2           3 . 3 . 3 . 3 . 3 . 3 . 3 . 3 .
 * 4   1           4 4 4 4 4 4 4 4 4 4 4 4 4 4 4 4
 */

/* Not using for now (probably will in the future)
typedef struct Frame_Block_struct Frame_Block;
struct Frame_Block_struct {
    mem_t address; // Start of Memory the block is tracking
    mem_t free; // Total Amount of memory that is free
    mem_t used; // Total Amount of memory that is used
    u1 frames[FRAMES];
};

Frame_Block * frame_blocks = (Frame_Block *) &KERNEL_HIGH_END;
mem_t frame_blocks_size = 0;
*/

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

#if 0
#define FRAME_IS_FREE(page) (!((page) & 1))
#define FRAME_LEVEL(page) ((page) >> 1)
#define FRAME_LEVEL_SIZE(level) (1 << (FRAME_LEVELS - level))
#define FRAME_MARK_FREE(page) (fb->frames[page] &= -2) // (-2 == 111..1110)
#define FRAME_MARK_USED(page) (fb->frames[page] |= 1)
#define FRAME_IS_RIGHT(page) (page) % (1 << (FRAME_LEVELS - PAGE_LEVEL(page)))

/* DEBUG FUNCTION
void print_frames(Frame_Block * fb) {
    for (u4 i = 0; i < FRAMES; i++) {
        u1 f = fb->frames[i];
        print_uint(FRAME_LEVEL(f));
        if (!FRAME_IS_FREE(f)) {
            print_string("*");
        }
    }
    print_char('\n');
}
*/

// Return true if an error occurred
bool Frame_Block_allocate(Frame_Block * fb, u2 frames, void ** address) {

    // Get Number of frames rounded to the next power of 2
    u4 level = 0;
    u4 rounded;
    while ((rounded = (1 << level)) < frames) {
        level++;
    }
    level = FRAME_LEVELS - level;
    //print_frames(fb);
    //print_format("Allocate:\n - Level is {d}\n - Find Exact Sized Free Buddy Block\n", level);

    // Find free Block Matching that rounded size exactly
    for (u4 i = 0; i < FRAMES; i += rounded) {
        u1 f = fb->frames[i];
        if (FRAME_IS_FREE(f) && FRAME_LEVEL(f) == level) {
            //print_format(" - Found at: {d}\n", i);
            FRAME_MARK_USED(i);
            *address = (void *) (fb->address + FRAME_SIZE * i);
            fb->free -= FRAME_LEVEL_SIZE(l);
            fb->used += FRAME_LEVEL_SIZE(l);
            return false;
        }
    }

    //print_format(" - Did not find exact size, Find Larger Block\n");
    // Find Larger Block to split
    u4 l = level;
    bool block_found = false;
    u4 i;
    while (true) {
        //print_format("    Level: {d}\n", l);
        for (i = 0; i < FRAMES; i += FRAME_LEVEL_SIZE(l)) {
            u1 f = fb->frames[i];
            if (FRAME_IS_FREE(f) && FRAME_LEVEL(f) == l) {
                // We found a block to split
                block_found = true;
                break;
            }
        }
        if ((!l) || block_found)
            // We're at the top or we found a block to split
            break;
        l--;
    }
    if (!block_found) {
        //print_string("    Larger Block NOT Found, Error\n");
        return true;
    }
    //print_format("    Larger Block Found at: {d}\n - Split it\n", i);

    // Split first part of the block until it's the same size
    for (; l < level;) {
        l++;
        //print_format("        L{d} ", l);
        //print_frames(fb);
        fb->frames[i] = l << 1;
        fb->frames[i + FRAME_LEVEL_SIZE(l)] = l << 1;
    }
    FRAME_MARK_USED(i);
    //print_frames(fb);
    fb->free -= FRAME_LEVEL_SIZE(l);
    fb->used += FRAME_LEVEL_SIZE(l);
    *address = (void *) (fb->address + FRAME_SIZE * i);
    return false;
}

// Return true if an error occurred
bool Frame_Block_deallocate(Frame_Block * fb, void * address) {
    u4 frame = (((u4) address) - ((u4) fb->address)) / FRAME_SIZE;
    FRAME_MARK_FREE(frame);

    // Merge buddy block with siblings until we find a used sibling or no more
    // siblings.
    u1 level = fb->frames[frame] >> 1;
    while (true) {
        u4 buddy_location = frame;
        u4 size = FRAME_LEVEL_SIZE(level);
        bool move_left;
        if (frame % (1 << (FRAME_LEVELS - level + 1))) {
            buddy_location -= size;
            move_left = true;
        } else {
            buddy_location += size;
            move_left = false;
        }
        u1 buddy = fb->frames[buddy_location];
        if (FRAME_IS_FREE(buddy) && (FRAME_LEVEL(buddy) == level)) {
            fb->frames[buddy_location] = 0;
            fb->frames[frame] = 0;
        } else {
            break;
        }
        if (move_left) {
            frame = buddy_location;
        }
        if (!level) { // No more siblings
            break;
        }
        level--;
    }
    fb->frames[frame] = level << 1;
    fb->free -= FRAME_LEVEL_SIZE(level);
    return false;
}
#endif
