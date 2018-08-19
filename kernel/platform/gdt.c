#include "gdt.h"
#include <platform.h>
#include <print.h>

u2 gdt_set_gate(u2 num, u4 base, u4 limit, u4 info) {
    gdt[num].limit_0_15 = limit & 0xFFFF;
    gdt[num].base_0_15 = base & 0xFFFF;
    gdt[num].base_16_23 = (base >> 16) & 0xFF;
    gdt[num].info = info & 0xFF;
    // Combine with 3rd Nibble of Info
    gdt[num].limit_16_19 = ((limit >> 16) & 0xF) | ((info & 0xF00) >> 4);
    gdt[num].base_24_31 = (base >> 24) & 0xFF;

    return num;
}

void gdt_initialize() {
    // Set Up Pointer
    gdt_pointer.limit = (sizeof(gdt_entry_t) * GDT_CNT) - 1;
    gdt_pointer.base = (u4) &gdt;

    // Required NULL Entry
    gdt_set_gate(0, 0, 0, 0);
    // Kernel Code Segment
    kernel_code_selector = (gdt_set_gate(
        1, 0, 0xFFFFFFFF, GDT_ENTRY | GDT_RING_0 | GDT_CODE_SEGMENT_ER
    ) << 3);
    // Kernel Data Segment
    kernel_data_selector = (gdt_set_gate(
        2, 0, 0xFFFFFFFF, GDT_ENTRY | GDT_RING_0 | GDT_DATA_SEGMENT_RW
    ) << 3);
    // User Code Segment
    user_code_selector = (gdt_set_gate(
        3, 0, 0xFFFFFFFF, GDT_ENTRY | GDT_RING_3 | GDT_CODE_SEGMENT_ER
    ) << 3) | 3;
    // User Data Segment
    user_data_selector = (gdt_set_gate(
        4, 0, 0xFFFFFFFF, GDT_ENTRY | GDT_RING_3 | GDT_DATA_SEGMENT_RW
    ) << 3) | 3;
    // Required Task State Segment
    memset(&tss, 0, sizeof(tss_t));
    tss.esp0 = 0;
    tss.ss0 = kernel_data_selector;
    tss_selector = (gdt_set_gate(
        5, (u4) &tss, sizeof(tss_t) - 1,
        GDT_RING_3 | GDT_TSS
    ) << 3) | 3;

    /*
    print_format(
        "kernel code selector: {x}\n"
        "kernel data selector: {x}\n"
        "user code selector: {x}\n"
        "user data selector: {x}\n",
        kernel_code_selector,
        kernel_data_selector,
        user_code_selector,
        user_data_selector
    );
    */

    // Load
    gdt_load();
}
