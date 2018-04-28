#include <library.h>
#include <print.h>
#include <kernel.h>
#include <memory.h>

#include "platform.h"
#include "../platform.h"

#include "multiboot.h"

void process_multiboot(multiboot_info_t* mb) {
    // Check if Memory Map is in place
    if (mb->flags & 64) { // 6ith bit
        multiboot_memory_map_t * begin = (multiboot_memory_map_t*) kernel_offset(mb->mmap_addr);
        multiboot_memory_map_t * end = ((void*) begin) + mb->mmap_length;
        multiboot_memory_map_t * e;
        for (e = begin; e < end; e = ((void*)e) + sizeof(e->size) + e->size) {
            if (e->type == MULTIBOOT_MEMORY_AVAILABLE) {
                memory_range_add(e->addr, e->len, FRAME_STACK_USE);
            }
        }
    } else {
        PANIC("Could not get memory map from multiboot!\n");
    }
    
}

void platform_init(multiboot_info_t* mb) {
    kernel_range = 1;
    fb_initialize();
    gdt_initialize();
    idt_initialize();
    //irq_initialize();
    process_multiboot(mb);
}
