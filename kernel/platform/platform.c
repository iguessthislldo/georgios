#include <library.h>
#include <print.h>
#include <kernel.h>
#include <memory.h>

#include "platform.h"

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

#define COM1 0x3f8
void serial_initialize() {
	out1(COM1 + 1, 0x00); // Disable all interrupts
	out1(COM1 + 3, 0x80); // Enable DLAB (set baud rate divisor)
	out1(COM1 + 0, 0x03); // Set divisor to 3 (lo byte) 38400 baud
	out1(COM1 + 1, 0x00); //                  (hi byte)
	out1(COM1 + 3, 0x03); // 8 bits, no parity, one stop bit
	out1(COM1 + 2, 0xC7); // Enable FIFO, clear them, with 14-byte threshold
	out1(COM1 + 4, 0x0B); // IRQs enabled, RTS/DSR set
	serial_log_enabled = true;
}

void serial_out(char c) {
    while (!(in1(COM1 + 5) & 0x20)) {}
    out1(COM1, c);
}

void platform_init(multiboot_info_t* mb) {
	serial_log_enabled = false;
    kernel_range = 1;
    serial_initialize();
    fb_initialize();
    gdt_initialize();
    idt_initialize();
    irq_initialize();
    ps2_init();
    process_multiboot(mb);
    find_pci_devices();
}

u4 tick_counter = 0;

void wait(u4 ticks) {
    ticks += tick_counter;
    while (tick_counter != ticks) {
        asm("nop");
    }
}
