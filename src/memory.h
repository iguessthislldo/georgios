/* ============================================================================
 * System Wide Memory Management
 * ============================================================================
 * Interface for Managing System Memory
 */

#ifndef MEMORY_HEADER
#define MEMROY_HEADER

#include <library.h> // normal types
#include <platform.h> // mem_t

/*
 * Add Range of Contiguous Memory, used when processing multiboot
 */
void memory_range_add(mem_t start, mem_t size);

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
bool allocate_vmem(void * address, mem_t size);

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

/*
 * Allocate Phycial Memory Frames at an address, called in peicemeal
 */
bool allocate_pmem(mem_t ammount, mem_t * got, void ** address);

bool deallocate_pmem(void * address);

/*
 * Stats
 *
 * Not valid until after memory_init() is called
 */

// Max Memory available given ideal conditions
mem_t memory_total;

// Total lost to Kernel and Rounding Memory Ranges
mem_t lost_total;

// Total Number of Frame Blocks in the system
mem_t block_total;

// Total amount of Memory that makes up used frames
mem_t memory_used;

#endif
