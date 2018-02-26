#ifndef X86_32_PAGING
#define X86_32_PAGING

#include <library.h>

#define PAGING_ADDRESS_MASK = 0xFFFFF000;

#define _pg_is_present(entry) ((entry) & 1)
#define _pg_get_address(entry) (entry)

#define GET_DIRECTORY_INDEX(address) ((((u4) address) & 0xFFC00000) >> 22)
#define GET_TABLE_INDEX(address) ((((u4) address) & 0x003FF000) >> 12)
#define GET_PAGE_INDEX(address) (((u4) address) & 0x00000FFF)
/*
 * Page Directory
 */
extern u4 page_directory[1024];

#if 0
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
#endif


//void identity_map(void * start, u4 ammount);

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
