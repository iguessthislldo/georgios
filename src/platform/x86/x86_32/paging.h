/* ===========================================================================
 * x86_32 Paging
 * ===========================================================================
 */

#ifndef X86_32_PAGING
#define X86_32_PAGING

#include <library.h> // normal types

// Values for use in memory.c
#define FRAME_SIZE 4096
#define FRAME_LEVELS 7

#define PAGING_ADDRESS_MASK = 0xFFFFF000;

#define PAGE_IS_PRESENT(entry) ((entry) & 1)
#define PAGE_GET_ADDRESS(entry) (entry & PAGING_ADDRESS_MASK)
#define GET_DIRECTORY_INDEX(address) ((((u4) address) & 0xFFC00000) >> 22)
#define GET_TABLE_INDEX(address) ((((u4) address) & 0x003FF000) >> 12)
#define GET_PAGE_INDEX(address) (((u4) address) & 0x00000FFF)

/*
 * Page Directory
 * Defined in boot.s
 */
extern u4 page_directory[1024];

/*
 * Paging Control Functions
 */
inline void enable_paging() {
    asm(
        "mov %0, %%cr3\n\t"
        "mov %%cr0, %0\n\t"
        "or $0x80000000, %0\n\t"
        "mov %0, %%cr0\n\t"
    ::
        "r" (page_directory)
    :
        "0"
    );
}

inline void disable_paging() {
    u4 value;
    asm __volatile__(
        "mov %%cr0, %0\n\t"
        "and $0x7FFFFFFF, %0\n\t"
        "mov %0, %%cr0\n\t"
    :
        "=r" (value)
    ::
        "0"
    );
}

#endif
