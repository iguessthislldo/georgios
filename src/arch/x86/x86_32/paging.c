#include "paging.h"

void page_directory_set(u4 index, page_directory_t pd) {
    u4 entry = pd.address;

    page_directory[index] = entry;
}

