#ifndef X86_32_PAGING
#define X86_32_PAGING

#include <library.h>
#include <frame.h>

#define PAGE_SIZE 4096
#define TABLE_COVERS PAGE_SIZE * 1024
#define FRAME_LEVELS 12 // 4096 * 4KiB Frames = 16MiB
#define FRAMES 1 << FRAME_LEVELS
Frame_Context fctx;
u1 frame_info[FRAMES];

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
 * Convert page_directory_t to 4 byte entry and place in the directory
 */
void page_directory_set(u4 index, page_directory_t pd);

/*
 * Convert Page Directory Entry to page_directory_t
 */
page_directory_t page_directory_get(u4 index);

struct page_table_struct {
    u4 address; // Page Address (20 bits)
    // 9, 10, 11 are not used by the CPU
    bool global; // 8 ignored if PGE is disable (the default)
    // 7 Should be zero
    bool dirty; // 6
    bool accessed; // 5
    bool cache_disabled; // 4
    bool write_through; // 3
    bool user; // 2
    bool writable; // 1
    bool present; // 0 When not set, the rest of the entry is ignored by the CPU
};
typedef struct page_table_struct page_table_t;

/* 
 * Convert page_table_t to 4 byte entry and place in a table
 */
void page_table_set(page_table_t pt);

/*
 * Get page_directory_t from address through the page tables
 */
page_table_t page_table_get(void * address);

void identity_map(void * start, u4 ammount);

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
