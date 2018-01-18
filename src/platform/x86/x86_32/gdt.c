#include "gdt.h"

void gdt_set_gate(u4 num, u4 base, u4 limit, u1 access, u1 gran) {
    gdt[num].base_low = (base & 0xFFFF);
    gdt[num].base_middle = (base >> 16) & 0xFF;
    gdt[num].base_high = (base >> 24) & 0xFF;
    gdt[num].limit_low = (limit & 0xFFFF);
    gdt[num].granularity = ((limit >> 16) & 0x0F);
    gdt[num].granularity |= (gran & 0xF0);
    gdt[num].access = access;
}

void gdt_initialize() {
    gdt_pointer.limit = (sizeof(gdt_entry_t) * 3) - 1;
    gdt_pointer.base = (u4) &gdt;

    // GDT
    gdt_set_gate(0, 0, 0, 0, 0);
        // Code Segment
    gdt_set_gate(1, 0, 0xFFFFFFFF, 0x9A, 0xCF);
        // Data Segment
    gdt_set_gate(2, 0, 0xFFFFFFFF, 0x92, 0xCF);

    gdt_load();
}
