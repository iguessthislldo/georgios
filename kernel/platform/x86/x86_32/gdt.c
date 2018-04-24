#include "gdt.h"

u1 gdt_set_gate(u4 num, u4 base, u4 limit, u1 access, u1 gran) {
    gdt[num].base_low = (base & 0xFFFF);
    gdt[num].base_middle = (base >> 16) & 0xFF;
    gdt[num].base_high = (base >> 24) & 0xFF;
    gdt[num].limit_low = (limit & 0xFFFF);
    gdt[num].granularity = ((limit >> 16) & 0x0F);
    gdt[num].granularity |= (gran & 0xF0);
    gdt[num].access = access;

    return num;
}

#define GDT_SEGMENT 0xCF
#define GDT_KERNEL 0x90
#define GDT_USER 0x90
#define GDT_CODE 0x0A
#define GDT_DATA 0x02

void gdt_initialize() {
    // Set Up Pointer
    gdt_pointer.limit = (sizeof(gdt_entry_t) * GDT_CNT) - 1;
    gdt_pointer.base = (u4) &gdt;

    // Required NULL Entry
    gdt_set_gate(0, 0, 0, 0, 0);
    // Kernel Code Segment
    kernel_code_selector = gdt_set_gate(
        1, 0, 0xFFFFFFFF, GDT_KERNEL | GDT_CODE, GDT_SEGMENT
    ) | RING_0;
    // Kernel Data Segment
    kernel_code_selector = gdt_set_gate(
        2, 0, 0xFFFFFFFF, GDT_KERNEL | GDT_DATA, GDT_SEGMENT
    ) | RING_0;
    // User Code Segment
    user_code_selector = gdt_set_gate(
        3, 0, 0xFFFFFFFF, GDT_USER | GDT_CODE, GDT_SEGMENT
    ) | RING_3;
    // User Data Segment
    user_data_selector = gdt_set_gate(
        4, 0, 0xFFFFFFFF, GDT_USER | GDT_DATA, GDT_SEGMENT
    ) | RING_3;
    // Required Task State Segment
    // TODO

    // Load
    gdt_load();
}
