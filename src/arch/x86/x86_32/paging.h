#ifndef X86_32_PAGING
#define X86_32_PAGING

#include <library.h>

extern u4 page_directory[1024];

/*
 * Used for easy access, not the final 4 byte entry
 */
struct page_directory_struct {
    u4 address; // Page Table Address
    // 8, 9, 10, 11 are not used by the CPU
    bool page_size; // 7
    // 6 should be zero
    bool accessed; // 5
    bool cache_disabled; // 4
    bool write_through; // 3
    bool user; // 2
    bool writable; // 1
    bool present; // 0 When not set, the rest of the entry is ignored by the CPU
};
typedef struct page_directory_struct page_directory_t;

/* 
 * Convert page_directory_t to 4 byte entry and place in array.
 */
void page_directory_set(u4 index, page_directory_t pd);

/*
 * Convert Page Directory Entry to page_directory_t
 */
page_directory_t page_directory_get(u4 index);

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
