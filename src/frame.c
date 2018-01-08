#include "frame.h"

#define FRAME_IS_FREE(page) (!((page) & 1))
#define FRAME_LEVEL(page) ((page) >> 1)
#define FRAME_LEVEL_SIZE(level) (1 << level)
#define FRAME_MARK_FREE(page) (fc.frame_info[page] &= -2) // (-2 == 111..1110)
#define FRAME_MARK_USED(page) (fc.frame_info[page] |= 1)
#define FRAME_IS_RIGHT(page) (page) % (1 << (fc.max_level - PAGE_LEVEL(page)))

void * allocate_frames(Frame_Context fc, u4 n) {
    // Get Number of frames rounded to the next power of 2
    //     Optimize using ffs/clz?
    u4 level = 0;
    u4 rounded;
    while ((rounded = (1 << level)) < n) {
        level++;
    }
    level = fc.max_level - level;

    // Find free Block Matching that rounded size exactly
    for (u4 i = 0; i < fc.frame_count; i += rounded) {
        u1 page = fc.frame_info[i];
        if (FRAME_IS_FREE(page) && FRAME_LEVEL(page) == level) {
            FRAME_MARK_USED(i);
            return fc.begin + fc.frame_size * i;
        }
    }

    // Find Larger Block
    u4 l = level;
    bool split_found = false;
    u4 i;
    while (true) {
        for (i = 0; i < fc.frame_count; i += FRAME_LEVEL_SIZE(l)) {
            u1 page = fc.frame_info[i];
            if (FRAME_IS_FREE(page) && FRAME_LEVEL(page) == l) {
                split_found = true;
                break;
            }
        }
        if ((!l) || split_found) break;
        l--;
    }
    if (!split_found) {
        return 0;
    }

    // Split first part of the block until it's the same size
    for (; l < level;) {
        l++;
        fc.frame_info[i] = l << 1;
        fc.frame_info[i + FRAME_LEVEL_SIZE(l)] = l << 1;
    }
    FRAME_MARK_USED(i);

    return fc.begin + fc.frame_size * i;
}

void deallocate_pages(Frame_Context fc, void * begin) {
    u4 page = (((u4) begin) - ((u4) fc.begin)) / fc.frame_size;
    FRAME_MARK_FREE(page);

    // Merge block with siblings until we find a used sibling or no more
    // siblings
    u1 level = fc.frame_info[page] >> 1;
    while (true) {
        u4 buddy_location = page;
        u4 size = FRAME_LEVEL_SIZE(level);
        bool move_left;
        if (page % (1 << (fc.max_level - level + 1))) {
            buddy_location -= size;
            move_left = true;
        } else {
            buddy_location += size;
            move_left = false;
        }
        u1 buddy = fc.frame_info[buddy_location];
        if (FRAME_IS_FREE(buddy) && (FRAME_LEVEL(buddy) == level)) {
            fc.frame_info[buddy_location] = 0;
            fc.frame_info[page] = 0;
        } else {
            break;
        }
        if (move_left) {
            page = buddy_location;
        }
        if (!level) break;
        level--;
    }
    fc.frame_info[page] = level << 1;
}
