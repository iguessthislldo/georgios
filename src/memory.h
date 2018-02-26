#ifndef MEMORY_HEADER
#define MEMROY_HEADER

#include <library.h>
#include <platform.h>

#define FRAME_SIZE 4096
#define FRAME_LEVELS 7
#define FRAMES (1 << FRAME_LEVELS) // 1<<7 = 128
#define FRAME_BLOCK_SIZE (FRAMES * FRAME_SIZE)
  // 128 * 4096 = 524288 B (1/2 MiB per Frame Block)

void memory_range_add(mem_t start, mem_t size);
mem_t memory_total, lost_total, block_total;

void memory_init();
void * allocate_frames(u2 n);

#endif
