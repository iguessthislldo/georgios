/* ===========================================================================
 * System Wide Memory Management
 * ===========================================================================
 * Interface for Managing System Memory
 */

#ifndef MEMORY_HEADER
#define MEMROY_HEADER

#include <basic_types.h>

/*
 * Memory Map
 * Represents contiguous physical memory sections that we can use
 */

typedef enum {
    DO_NOT_USE, // Do not use through allocators
    BLOCK_ALLOCATOR_USE, // Contigous Buddy System based Allocation (TODO)
    FRAME_STACK_USE // Break up into Frames and Allocate on a stack
} Memory_Range_Use;

typedef struct {
    mem_t start;
    mem_t size;
    Memory_Range_Use use;
} Memory_Range;

#define MEMORY_RANGE_MAX 64
Memory_Range memory_map[MEMORY_RANGE_MAX];
u1 memory_range_num;
u1 kernel_range;

/*
 * Add Range of Contiguous Memory, used when processing multiboot
 */
void memory_range_add(mem_t start, mem_t size, Memory_Range_Use use);

/*
 * Initialize Memory Management
 */
void memory_init();

/*
 * Allocate a virtual memory range
 * **PLATFORM DEFINED**
 *
 * address
 *     address of the range in virtual memory
 * size
 *     size of the range that will rounded up by FRAME_SIZE.
 *
 * returns true if there was an error
 */
bool allocate_vmem(mem_t address, mem_t size);

/*
 * Deallocate a virtual memory range
 * **PLATFORM DEFINED**
 *
 * address
 *     address of the range in virtual memory
 * size
 *     size of the range that will rounded up by FRAME_SIZE.
 *
 * returns true if there was an error
 */
bool deallocate_vmem(void * address, mem_t size);

bool pop_frame(mem_t * address);
void push_frame(mem_t address);

/*
 * Allocate Phycial Memory Frames at an address, called in peicemeal
 * Used by platform defined virtual memory allocation implementation.
 *
 * left
 *     Pointer to how much memory is left to allocate.
 *     Initialize with ammount desired and run until 0.
 * got
 *     Pointer to how much it got for use in the virutal memory.
 * address
 *     On success is set to the address of the allocated range.
 *
 * Returns true if there was an error
 *
 * Exampe:
 *     mem_t left = KiB(10);
 *     mem_t got;
 *     void * address;
 *     while (left) {
 *         if (allocate_pmem(&left, &got, &address)) continue;
 *         // Set virtual memory using address and got
 *     }
 */
extern bool allocate_pmem(mem_t * left, mem_t * got, void ** address);

/*
 * Allocate Phycial Memory Frames at an address, called in peicemeal
 * like allocate_pmem,
 */
extern bool deallocate_pmem(void * address);

/*
 * Stats
 *
 * Not valid until after memory_init() is called
 */

// Max Memory available given ideal conditions
mem_t memory_total;

// Total Number of Frames in Stack
mem_t frame_stack_count;

// Total amount of Memory that makes up used frames
mem_t memory_used;

#endif
