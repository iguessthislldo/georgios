/*
 * Global Descriptor Table
 *
 * Referneces:
 *   http://www.flingos.co.uk/docs/reference/Global-Descriptor-Table/
 *   https://web.archive.org/web/20160327011227/http://www.jamesmolloy.co.uk:80/tutorial_html/4.-The%20GDT%20and%20IDT.html
 */

#ifndef X86_GDT_HEADER
#define X86_GDT_HEADER

#include <library.h>

struct gdt_entry_struct {
	u2 limit_low;
	u2 base_low;
	u1 base_middle;
	u1 access;
	u1 granularity;
	u1 base_high;
} __attribute__((packed));
typedef struct gdt_entry_struct gdt_entry_t;

struct gdt_pointer_struct {
	u2 limit;
	u4 base;
} __attribute__((packed));
typedef struct gdt_pointer_struct gdt_pointer_t;

#define GDT_CNT 6
gdt_entry_t gdt[GDT_CNT];
gdt_pointer_t gdt_pointer;

#define RING_0 0
#define RING_1 1
#define RING_2 2
#define RING_3 3

u1 kernel_code_selector;
u1 kernel_data_selector;
u1 user_code_selector;
u1 user_data_selector;

extern void gdt_load();

u1 gdt_set_gate(u4 num, u4 base, u4 limit, u1 access, u1 gran);
void gdt_initialize();

#endif
