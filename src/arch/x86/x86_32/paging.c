#include "paging.h"

const u4 address_mask = 0xFFFFF000;

void page_directory_set(u4 index, page_directory_t pd) {
    u4 entry = 0;
    
    if (pd.present) {
        entry = pd.address & address_mask;
        entry |= pd.present;
        entry |= pd.writable << 1;
        entry |= pd.user << 2;
        entry |= pd.write_through << 3;
        entry |= pd.cache_disabled << 4;
        entry |= pd.accessed << 5;
        entry |= pd.page_size << 7;
    }

    page_directory[index] = entry;
}

#define B(bit) (entry & (1 << bit)) ? 1 : 0
page_directory_t page_directory_get(u4 index) {
    u4 entry = page_directory[index];
    page_directory_t pd = (const page_directory_t){0};

    if (entry & 1) { // If Present
        pd.address = entry & address_mask;
        pd.present = true;
        pd.writable = B(1);
        pd.user = B(2);
        pd.write_through = B(3);
        pd.cache_disabled = B(4);
        pd.accessed = B(5);
        pd.page_size = B(7);
    }

    return pd;
}
