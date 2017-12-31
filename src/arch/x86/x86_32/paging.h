#ifndef X86_32_PAGING
#define X86_32_PAGING

#include <library.h>

extern u4 page_directory[1024];

/*
 * Used for easy access, not the final 4 byte entry
 */
struct page_directory_struct {
    u4 address; // Page Table
    u2 extra; // Not used by the CPU
    bool zero; // 6 
    bool accessed; // 5
    bool cache_disabled; // 4
    bool write_through; // 3
    bool user; // 2
    bool read; // 1
    bool present; // 0 When not set, the rest of the entry is ignored by the CPU
};
typedef struct page_directory_struct page_directory_t;

void page_directory_set(u4 index, page_directory_t pd);

page_directory_t page_directory_get(u4 index);

inline void enable_paging() {
    
}

inline void disable_paging() {
}

#endif
