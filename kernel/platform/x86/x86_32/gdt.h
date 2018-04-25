/*
 * Global Descriptor Table
 *
 * Referneces:
 *   http://www.flingos.co.uk/docs/reference/Global-Descriptor-Table/
 *   https://web.archive.org/web/20160327011227/http://www.jamesmolloy.co.uk:80/tutorial_html/4.-The%20GDT%20and%20IDT.html
 *   Intel 64 and IA-32 Architectures Software Developers Mannual Volume 3:
 *       3.4.5 Segment Descriptors
 */

#ifndef X86_GDT_HEADER
#define X86_GDT_HEADER

#include <library.h>

typedef struct {
    u2 limit_0_15;
    u2 base_0_15;
    u1 base_16_23;
    u1 info;
    u1 limit_16_19;
    u1 base_24_31;
} __attribute__((packed)) gdt_entry_t;

// gdt_entry_t info values
//   info[7:0] is gdt_entry_t[15:8]
//   info[11:8] is gdt_entry_t[20:23]
//   Default Values for Entry:
//     P, G, D/B, and AVL are set
#define GDT_ENTRY 0xC80
//     Type[5:0]
#define GDT_DATA_SEGMENT_RO 0x010
#define GDT_DATA_SEGMENT_RW 0x012
#define GDT_CODE_SEGMENT_EO 0x018
#define GDT_CODE_SEGMENT_ER 0x01A
#define GDT_TSS 0x089
//     Descriptor Privilege Level[6:5]
#define GDT_RING_0 0x000 // 0 << 5
#define GDT_RING_1 0x020 // 1 << 5
#define GDT_RING_2 0x040 // 2 << 5
#define GDT_RING_3 0x060 // 3 << 5

typedef struct {
    u2 limit;
    u4 base;
} __attribute__((packed)) gdt_pointer_t;

#define GDT_CNT 6
gdt_entry_t gdt[GDT_CNT];
gdt_pointer_t gdt_pointer;

typedef struct {
    u2 link, zero1;
    u4 esp0;
    u2 ss0, zero2;
    u4 esp1;
    u2 ss1, zero3;
    u4 esp3;
    u2 ss2, zero4;
    u4 cr3, eip, eflags, eax, ecx, edx, ebx, esp, ebp, esi, edi;
    u2 es, zero5, cs, zero6, ss, zero7, ds, zero8, fs, zero9, gs, zero10;
    u2 ldt_selector, zero11, trap, io_map;
} __attribute__((packed)) tss_t;

tss_t tss;

u2 kernel_code_selector;
u2 kernel_data_selector;
u2 user_code_selector;
u2 user_data_selector;
u2 tss_selector;

extern void gdt_load();

u2 gdt_set_gate(u2 num, u4 base, u4 limit, u4 info);
void gdt_initialize();

#endif
