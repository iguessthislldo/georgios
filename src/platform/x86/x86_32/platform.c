#include <library.h>
#include <print.h>
#include <kernel.h>

#include "platform.h"
#include "../platform.h"

#include "multiboot.h"

void platform_init(multiboot_info_t* mb) {
    fb_initialize();

    // Check if Memory Map is in place
    if (mb->flags & 64) { // 6ith bit
        u4 memory = 0;
        print_string("Got Memory Map from multiboot\n");
        multiboot_memory_map_t * begin = kernel_offset(mb->mmap_addr);
        multiboot_memory_map_t * end = ((u1*) begin) + mb->mmap_length;
        multiboot_memory_map_t * e;
        for (e = begin; e < end; e = ((u1*)e) + sizeof(e->size) + e->size) {
            if (e->type == MULTIBOOT_MEMORY_AVAILABLE) {
                print_format(" - {d} (", e->addr);
                print_format("{d})\n", e->len);
                memory += e->len;
            }
        }
        print_format("Kernel has {d} bytes (", memory);
        print_format("{d} MiB) of memory available to it\n", memory >> 20);
    } else {
        print_string("Could not get memory map from multiboot!\n");
        halt();
    }
    
    gdt_initialize();
    idt_initialize();
    irq_initialize();
}
