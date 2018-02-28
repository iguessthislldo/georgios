/* ===========================================================================
 * x86_32 Paging
 * ===========================================================================
 */

#include "paging.h"
#include <print.h>

/*
void identity_map(void * start, u4 ammount) {
    void * end = start + ammount;
    const u4 dstart = GET_DIRECTORY_INDEX(start);
    const u4 dend = GET_DIRECTORY_INDEX(end);
    u4 ntables = dend - dstart;

    // Allocate Tables
    u4 * page_tables = allocate_frames(fctx, ntables);

    // Update Page Directory
    for (u2 i = dstart; i < dend; i++) {
        page_directory[i] = (((u4) page_tables) + i * 4096) | 1;
        print_format("PD[{d}] = {x}\n", i, page_directory[i]);
    }

    // Populate Tables
    u4 npages = ntables * 1024;
    u4 * p = (u4*) start;
    for (u4 i = 0; i < npages; i++) {
        page_tables[i] = (u4) p | 1;
        p += 1024;
    }
}
*/
