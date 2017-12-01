#ifndef X86_GDT_HEADER
#define X86_GDT_HEADER

#include <stdint.h>

struct gdt_entry_struct {
	uint16_t limit_low;
	uint16_t base_low;
	uint8_t base_middle;
	uint8_t access;
	uint8_t granularity;
	uint8_t base_high;
} __attribute__((packed));
typedef struct gdt_entry_struct gdt_entry_t;

struct gdt_pointer_struct {
	uint16_t limit;
	uint32_t base;
} __attribute__((packed));
typedef struct gdt_pointer_struct gdt_pointer_t;

gdt_entry_t gdt[3];
gdt_pointer_t gdt_pointer;

extern void gdt_load();

void gdt_set_gate(int num, uint64_t base, uint64_t limit, uint8_t access, uint8_t gran);
void gdt_initialize();

#endif
