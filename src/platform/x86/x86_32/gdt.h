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

gdt_entry_t gdt[3];
gdt_pointer_t gdt_pointer;

extern void gdt_load();

void gdt_set_gate(u4 num, u4 base, u4 limit, u1 access, u1 gran);
void gdt_initialize();

#endif