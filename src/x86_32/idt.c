#include "idt.h"
#include "../string.h"
#include "fb.h"

void idt_set(uint8_t index, uint32_t base, uint16_t select, uint8_t flags) {
    idt[index].base_low = base & 0xFFFF;
    idt[index].base_high = (base & 0xFFFF0000) >> 16;
    idt[index].select = select;
    idt[index].zero = 0;
    idt[index].flags = flags;
}

void idt_initialize() {
    idt_pointer.limit = (sizeof(idt_entry_t) * IDT_SIZE);
    idt_pointer.base = (uint32_t) &idt;
    memset(&idt, 0, sizeof(idt_entry_t) * IDT_SIZE);
    idt_set(0, (uint32_t) ih_0, 0x08, 0x8E);
    idt_set(1, (uint32_t) ih_1, 0x08, 0x8E);
    idt_set(2, (uint32_t) ih_2, 0x08, 0x8E);
    idt_set(3, (uint32_t) ih_3, 0x08, 0x8E);
    idt_set(4, (uint32_t) ih_4, 0x08, 0x8E);
    idt_set(5, (uint32_t) ih_5, 0x08, 0x8E);
    idt_set(6, (uint32_t) ih_6, 0x08, 0x8E);
    idt_set(7, (uint32_t) ih_7, 0x08, 0x8E);
    idt_set(8, (uint32_t) ih_8, 0x08, 0x8E);
    idt_set(9, (uint32_t) ih_9, 0x08, 0x8E);
    idt_set(10, (uint32_t) ih_10, 0x08, 0x8E);
    idt_set(11, (uint32_t) ih_11, 0x08, 0x8E);
    idt_set(12, (uint32_t) ih_12, 0x08, 0x8E);
    idt_set(13, (uint32_t) ih_13, 0x08, 0x8E);
    idt_set(14, (uint32_t) ih_14, 0x08, 0x8E);
    idt_set(15, (uint32_t) ih_15, 0x08, 0x8E);
    idt_set(16, (uint32_t) ih_16, 0x08, 0x8E);
    idt_set(17, (uint32_t) ih_17, 0x08, 0x8E);
    idt_set(18, (uint32_t) ih_18, 0x08, 0x8E);
    idt_set(19, (uint32_t) ih_19, 0x08, 0x8E);
    idt_set(20, (uint32_t) ih_20, 0x08, 0x8E);
    idt_set(21, (uint32_t) ih_21, 0x08, 0x8E);
    idt_set(22, (uint32_t) ih_22, 0x08, 0x8E);
    idt_set(23, (uint32_t) ih_23, 0x08, 0x8E);
    idt_set(24, (uint32_t) ih_24, 0x08, 0x8E);
    idt_set(25, (uint32_t) ih_25, 0x08, 0x8E);
    idt_set(26, (uint32_t) ih_26, 0x08, 0x8E);
    idt_set(27, (uint32_t) ih_27, 0x08, 0x8E);
    idt_set(28, (uint32_t) ih_28, 0x08, 0x8E);
    idt_set(29, (uint32_t) ih_29, 0x08, 0x8E);
    idt_set(30, (uint32_t) ih_30, 0x08, 0x8E);
    idt_set(31, (uint32_t) ih_31, 0x08, 0x8E);
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
