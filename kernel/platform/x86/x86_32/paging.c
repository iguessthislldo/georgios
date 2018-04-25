/* ===========================================================================
 * x86_32 Paging
 * ===========================================================================
 */

#include "paging.h"

#include <kernel.h>
#include <print.h>
#include <memory.h>

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

void load_table(mem_t address) {
    mem_t directory_index = GET_DIRECTORY_INDEX(address);
    mem_t table;
    mem_t temp_table_index = GET_TABLE_INDEX(&temp_page_table[0]);
    if (page_directory[directory_index] & 1) {
        table = PAGE_GET_ADDRESS(page_directory[directory_index]);
    } else {
        if (pop_frame(&table)) {
            PANIC("load_table could not load a new table");
        }
        page_directory[directory_index] = 0;
        page_directory[directory_index] = table | 1;
    }
    asm volatile ("invlpg (%0)" :: "b"(&temp_page_table[0]) : "memory");
    kernel_page_table[temp_table_index] = table | 1;
}

bool allocate_vmem(mem_t address, mem_t ammount) {
    if (ammount) {
        // Get Address Rounded Down
        address = PAGE_GET_ADDRESS(address);

        // Get Ammount Rounded Up
        mem_t rem = ammount % FRAME_SIZE;
        if (rem) {
            ammount += rem;
        }

        mem_t ammount_left = ammount;
        mem_t tables_count = ammount / TABLE_SIZE;
        if (!tables_count) tables_count = 1;
        while (ammount_left) {
            mem_t directory_index = GET_DIRECTORY_INDEX(address);
            load_table(address); // Load table into temp_page_table
            mem_t page_start = GET_TABLE_INDEX(address);
            mem_t page_count;
            if (ammount_left > TABLE_SIZE) {
                page_count = TABLE_COUNT;
            } else {
                page_count = ammount_left / FRAME_SIZE;
            }
            mem_t page_end = page_start + page_count;
            for (mem_t i = page_start; i < page_end; i++) {
                mem_t t;
                pop_frame(&t);
                temp_page_table[i] = t | 1;
                address += FRAME_SIZE;
                ammount_left -= FRAME_SIZE;
            }
            mem_t table = PAGE_GET_ADDRESS(page_directory[directory_index]);
            page_directory[directory_index] = 0;
            page_directory[directory_index] = table | 1;
        }
        return false;
    }
    return true;
}

