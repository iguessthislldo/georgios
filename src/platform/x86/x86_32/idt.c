#include "idt.h"

#include <print.h>

void idt_set(u1 index, u4 base, u2 select, u1 flags) {
    idt[index].base_low = base & 0xFFFF;
    idt[index].base_high = (base & 0xFFFF0000) >> 16;
    idt[index].select = select;
    idt[index].zero = 0;
    idt[index].flags = flags;
}

void idt_initialize() {
    idt_pointer.limit = (sizeof(idt_entry_t) * IDT_SIZE);
    idt_pointer.base = (u4) &idt;
    memset(&idt, 0, sizeof(idt_entry_t) * IDT_SIZE);
    idt_set(0, (u4) ih_0, 0x08, 0x8E);
    idt_set(1, (u4) ih_1, 0x08, 0x8E);
    idt_set(2, (u4) ih_2, 0x08, 0x8E);
    idt_set(3, (u4) ih_3, 0x08, 0x8E);
    idt_set(4, (u4) ih_4, 0x08, 0x8E);
    idt_set(5, (u4) ih_5, 0x08, 0x8E);
    idt_set(6, (u4) ih_6, 0x08, 0x8E);
    idt_set(7, (u4) ih_7, 0x08, 0x8E);
    idt_set(8, (u4) ih_8, 0x08, 0x8E);
    idt_set(9, (u4) ih_9, 0x08, 0x8E);
    idt_set(10, (u4) ih_10, 0x08, 0x8E);
    idt_set(11, (u4) ih_11, 0x08, 0x8E);
    idt_set(12, (u4) ih_12, 0x08, 0x8E);
    idt_set(13, (u4) ih_13, 0x08, 0x8E);
    idt_set(14, (u4) ih_14, 0x08, 0x8E);
    idt_set(15, (u4) ih_15, 0x08, 0x8E);
    idt_set(16, (u4) ih_16, 0x08, 0x8E);
    idt_set(17, (u4) ih_17, 0x08, 0x8E);
    idt_set(18, (u4) ih_18, 0x08, 0x8E);
    idt_set(19, (u4) ih_19, 0x08, 0x8E);
    idt_set(20, (u4) ih_20, 0x08, 0x8E);
    idt_set(21, (u4) ih_21, 0x08, 0x8E);
    idt_set(22, (u4) ih_22, 0x08, 0x8E);
    idt_set(23, (u4) ih_23, 0x08, 0x8E);
    idt_set(24, (u4) ih_24, 0x08, 0x8E);
    idt_set(25, (u4) ih_25, 0x08, 0x8E);
    idt_set(26, (u4) ih_26, 0x08, 0x8E);
    idt_set(27, (u4) ih_27, 0x08, 0x8E);
    idt_set(28, (u4) ih_28, 0x08, 0x8E);
    idt_set(29, (u4) ih_29, 0x08, 0x8E);
    idt_set(30, (u4) ih_30, 0x08, 0x8E);
    idt_set(31, (u4) ih_31, 0x08, 0x8E);
    idt_load();
}

void idt_set_handler(u1 index, void (*handler)()) {
    idt_set(index, (u4) handler, 0x08, 0x8E);
    idt_load();
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
    "Reserved",
};

/*
*/
#define BOCHS_BREAK asm("xchgw %bx, %bx");

void x86_exception_handler(
   u4 ss, u4 gs, u4 fs, u4 es, u4 ds, u4 idt_index, u4 error_code
) {
    print_string("<Interrupt ");
    print_uint(idt_index);
    print_char("(");
    print_uint(error_code);
    print_string("): \"");
    if (idt_index < 32) {
        print_string(x86_exception_messages[idt_index]);
    } else {
        print_string("No message found for this exception");
    }
    if (idt_index == 32) {
        out1(PIT_0_7_COMMAND, PIT_RESET);
    }
    print_string("\">\n");
}

