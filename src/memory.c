#include <kernel.h>
#include <memory.h>
#include <print.h>

mem_t memory_total = 0;
mem_t lost_total = 0;
mem_t blocks_total = 0;

/* ============================================================================
 * Memory Map
 * ============================================================================
 * Represents contiguous memory sections that we can use
 */

typedef struct Memory_Range_struct Memory_Range;
struct Memory_Range_struct {
    mem_t start;
    mem_t size;
    mem_t blocks;
};

#define MEMORY_RANGE_MAX 16
Memory_Range memory_map[MEMORY_RANGE_MAX];
u1 memory_range_num = 0;

/*
 * Add Range of Contiguous Memory, used when processing multiboot
 */
void memory_range_add(mem_t start, mem_t size) {
    if (memory_range_num < MEMORY_RANGE_MAX) {
        memory_map[memory_range_num].start = start;
        memory_map[memory_range_num].size = size;
        mem_t blocks = size / FRAME_BLOCK_SIZE;
        blocks_total += blocks;
        mem_t blocks_size = blocks * FRAME_BLOCK_SIZE;
        memory_map[memory_range_num].blocks = blocks;
        memory_total += blocks_size;
        lost_total += size - blocks_size;
        memory_range_num++;
    }
}

/* ============================================================================
 * Frame Allocation
 * ============================================================================
 * Allocate Frames of Physical Memory in groups called Frame Blocks.
 * Frame Blocks use Buddy System allocation to allocate frames.
 */

typedef struct Frame_Block_struct Frame_Block;
struct Frame_Block_struct {
    mem_t address;
    u1 frames[FRAMES];
};

Frame_Block * frame_blocks = (Frame_Block *) &KERNEL_HIGH_END;
mem_t frame_blocks_size = 0;

void Frame_Block_init(Frame_Block * fb, mem_t address) {
    fb->address = address;
    for (u4 i = 0; i < FRAMES; i++) {
        fb->frames[i] = 0;
    }
}

void memory_init() {
    // Calculate size of Frame Block Array
    mem_t lost = (mem_t) &KERNEL_SIZE;
    frame_blocks_size = ((memory_total - lost) * sizeof(Frame_Block)) /
        (FRAME_BLOCK_SIZE + sizeof(Frame_Block));
    lost += frame_blocks_size;
    lost_total += lost;
    memory_total -= lost;

    // Initialize Frame Blocks
    mem_t address;
    mem_t blocks;
    Frame_Block * b = frame_blocks;
    for (u1 m = 0; m < memory_range_num; m++) {
        address = memory_map[m].start;
        blocks = memory_map[m].blocks;
        if ( // If Kernel is in this range
            (address <= (mem_t) &KERNEL_LOW_START) &&
            (address + memory_map[m].size > (mem_t) &KERNEL_LOW_END)
        ) { // then account for the Kernel and Frame Blocks
            address += lost;
            blocks -= lost / FRAME_BLOCK_SIZE;
        }
        for (mem_t i = 0; i < blocks; i++) {
            Frame_Block_init(b++, address);
            address += FRAME_BLOCK_SIZE;
        }
    }
}

#define FRAME_IS_FREE(page) (!((page) & 1))
#define FRAME_LEVEL(page) ((page) >> 1)
#define FRAME_LEVEL_SIZE(level) (1 << (FRAME_LEVELS - level))
#define FRAME_MARK_FREE(page) (fb->frames[page] &= -2) // (-2 == 111..1110)
#define FRAME_MARK_USED(page) (fb->frames[page] |= 1)
#define FRAME_IS_RIGHT(page) (page) % (1 << (FRAME_LEVELS - PAGE_LEVEL(page)))

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

void * Frame_Block_allocate(Frame_Block * fb, u2 n) {
    // Get Number of frames rounded to the next power of 2
    u4 level = 0;
    u4 rounded;
    while ((rounded = (1 << level)) < n) {
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
            return (void *) (fb->address + FRAME_SIZE * i);
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
        return 0;
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

    return (void *) (fb->address + FRAME_SIZE * i);
}

void Frame_Block_deallocate(Frame_Block * fb, void * address) {
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
        if (!level) break;
        level--;
    }
    fb->frames[frame] = level << 1;
}

void * allocate_frames(u2 n) {
    void * result;
    for (u1 m = 0; m < memory_range_num; m++) {
        u4 blocks = memory_map[m].blocks;
        for (u4 i = 0; i < blocks; i++) {
            if ((result = Frame_Block_allocate(&frame_blocks[i], n))) {
                return result;
            }
        }
    }
    return 0;
}
