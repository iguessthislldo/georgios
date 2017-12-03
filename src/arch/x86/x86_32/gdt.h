#ifndef X86_GDT_HEADER
#define X86_GDT_HEADER

#include <library.h>

struct gdt_entry_struct {
	u16 limit_low;
	u16 base_low;
	u8 base_middle;
	u8 access;
	u8 granularity;
	u8 base_high;
} __attribute__((packed));
typedef struct gdt_entry_struct gdt_entry_t;

struct gdt_pointer_struct {
	u16 limit;
	u32 base;
} __attribute__((packed));
typedef struct gdt_pointer_struct gdt_pointer_t;

gdt_entry_t gdt[3];
gdt_pointer_t gdt_pointer;

extern void gdt_load();

void gdt_set_gate(u32 num, u32 base, u32 limit, u8 access, u8 gran);
void gdt_initialize();

#endif
