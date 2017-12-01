#include "idt.h"
#include "fb.h"

void idt_set(u8 index, u32 base, u16 select, u8 flags) {
    idt[index].base_low = base & 0xFFFF;
    idt[index].base_high = (base & 0xFFFF0000) >> 16;
    idt[index].select = select;
    idt[index].zero = 0;
    idt[index].flags = flags;
}

void idt_initialize() {
    idt_pointer.limit = (sizeof(idt_entry_t) * IDT_SIZE);
    idt_pointer.base = (u32) &idt;
    memset(&idt, 0, sizeof(idt_entry_t) * IDT_SIZE);
    idt_set(0, (u32) ih_0, 0x08, 0x8E);
    idt_set(1, (u32) ih_1, 0x08, 0x8E);
    idt_set(2, (u32) ih_2, 0x08, 0x8E);
    idt_set(3, (u32) ih_3, 0x08, 0x8E);
    idt_set(4, (u32) ih_4, 0x08, 0x8E);
    idt_set(5, (u32) ih_5, 0x08, 0x8E);
    idt_set(6, (u32) ih_6, 0x08, 0x8E);
    idt_set(7, (u32) ih_7, 0x08, 0x8E);
    idt_set(8, (u32) ih_8, 0x08, 0x8E);
    idt_set(9, (u32) ih_9, 0x08, 0x8E);
    idt_set(10, (u32) ih_10, 0x08, 0x8E);
    idt_set(11, (u32) ih_11, 0x08, 0x8E);
    idt_set(12, (u32) ih_12, 0x08, 0x8E);
    idt_set(13, (u32) ih_13, 0x08, 0x8E);
    idt_set(14, (u32) ih_14, 0x08, 0x8E);
    idt_set(15, (u32) ih_15, 0x08, 0x8E);
    idt_set(16, (u32) ih_16, 0x08, 0x8E);
    idt_set(17, (u32) ih_17, 0x08, 0x8E);
    idt_set(18, (u32) ih_18, 0x08, 0x8E);
    idt_set(19, (u32) ih_19, 0x08, 0x8E);
    idt_set(20, (u32) ih_20, 0x08, 0x8E);
    idt_set(21, (u32) ih_21, 0x08, 0x8E);
    idt_set(22, (u32) ih_22, 0x08, 0x8E);
    idt_set(23, (u32) ih_23, 0x08, 0x8E);
    idt_set(24, (u32) ih_24, 0x08, 0x8E);
    idt_set(25, (u32) ih_25, 0x08, 0x8E);
    idt_set(26, (u32) ih_26, 0x08, 0x8E);
    idt_set(27, (u32) ih_27, 0x08, 0x8E);
    idt_set(28, (u32) ih_28, 0x08, 0x8E);
    idt_set(29, (u32) ih_29, 0x08, 0x8E);
    idt_set(30, (u32) ih_30, 0x08, 0x8E);
    idt_set(31, (u32) ih_31, 0x08, 0x8E);
    asm volatile ("lidt (%0)" : : "r" (&idt_pointer));
}

const char * x86_exception_messages[] = {
    "Divide by Zero Fault",
    "Debug Trap",
    "Nonmaskable Interrupt",
    "Breakpoint Trap",
    "Overflow Trap",
    "Bounds Fault",
    "Invalid Opcode",
    "Device Not Available",
    "Double Fault",
    "Coprocessor Segment Overrun",
    "Invalid TSS",
    "Segment Not Present",
    "Stack-Segment Fault",
    "General Protection Fault",
    "Page Fault",
    "Reserved",
    "x87 Floating-Point Exception",
    "Alignment Check",
    "Machine Check",
    "SIMD Floating-Point Exception",
    "Virtualization Exception",
    "Reserved",
    "Reserved",
    "Reserved",
    "Reserved",
    "Reserved",
    "Reserved",
    "Reserved",
    "Reserved",
    "Reserved",
    "Security Exception",
    "Reserved"
};

/*
#define BOCHS_BREAK asm("xchgw %bx, %bx");
BOCHS_BREAK
*/

void x86_exception_handler(x86_exception_t e) {
    fb_print_string("<Interrupt ");
    fb_print_uint(e.idt_index);
    fb_print_string(": \"");
    if (e.idt_index < 32) {
        fb_print_string(x86_exception_messages[e.idt_index]);
    } else {
        fb_print_string("No message found for this exception");
    }
    fb_print_string("\">\n");
    halt();
}
