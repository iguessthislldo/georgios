#include "idt.h"

#include <library.h>
#include <print.h>
#include <kernel.h>

#include <cga_console.h>

const char * panic_message = 0;

void idt_set(u1 index, u4 offset, u2 selector, u1 flags) {
    idt[index].offset_0_15 = offset & 0xFFFF;
    idt[index].offset_16_31= (offset & 0xFFFF0000) >> 16;
    idt[index].selector = selector;
    idt[index].zero = 0;
    idt[index].flags = flags;
}

#define DEFAULT_FLAGS 0x8E
#define KERNEL_INT kernel_code_selector, DEFAULT_FLAGS
#define USER_INT kernel_code_selector, DEFAULT_FLAGS | (3 << 5)

void idt_initialize() {
    idt_pointer.limit = (sizeof(idt_entry_t) * IDT_SIZE);
    idt_pointer.base = (u4) &idt;
    memset(&idt, 0, sizeof(idt_entry_t) * IDT_SIZE);
    idt_set(0, (u4) ih_0, KERNEL_INT);
    idt_set(1, (u4) ih_1, KERNEL_INT);
    idt_set(2, (u4) ih_2, KERNEL_INT);
    idt_set(3, (u4) ih_3, KERNEL_INT);
    idt_set(4, (u4) ih_4, KERNEL_INT);
    idt_set(5, (u4) ih_5, KERNEL_INT);
    idt_set(6, (u4) ih_6, KERNEL_INT);
    idt_set(7, (u4) ih_7, KERNEL_INT);
    idt_set(8, (u4) ih_8, KERNEL_INT);
    idt_set(9, (u4) ih_9, KERNEL_INT);
    idt_set(10, (u4) ih_10, KERNEL_INT);
    idt_set(11, (u4) ih_11, KERNEL_INT);
    idt_set(12, (u4) ih_12, KERNEL_INT);
    idt_set(13, (u4) ih_13, KERNEL_INT);
    idt_set(14, (u4) ih_14, KERNEL_INT);
    idt_set(15, (u4) ih_15, KERNEL_INT);
    idt_set(16, (u4) ih_16, KERNEL_INT);
    idt_set(17, (u4) ih_17, KERNEL_INT);
    idt_set(18, (u4) ih_18, KERNEL_INT);
    idt_set(19, (u4) ih_19, KERNEL_INT);
    idt_set(20, (u4) ih_20, KERNEL_INT);
    idt_set(21, (u4) ih_21, KERNEL_INT);
    idt_set(22, (u4) ih_22, KERNEL_INT);
    idt_set(23, (u4) ih_23, KERNEL_INT);
    idt_set(24, (u4) ih_24, KERNEL_INT);
    idt_set(25, (u4) ih_25, KERNEL_INT);
    idt_set(26, (u4) ih_26, KERNEL_INT);
    idt_set(27, (u4) ih_27, KERNEL_INT);
    idt_set(28, (u4) ih_28, KERNEL_INT);
    idt_set(29, (u4) ih_29, KERNEL_INT);
    idt_set(30, (u4) ih_30, KERNEL_INT);
    idt_set(31, (u4) ih_31, KERNEL_INT);

    idt_set(50, (u4) ih_panic, KERNEL_INT);
    idt_set(100, (u4) ih_system_call, USER_INT);

    idt_load();
}

void idt_set_handler(u1 index, void (*handler)()) {
    idt_set(index, (u4) handler, KERNEL_INT);
    idt_load();
}

const char * x86_interrupt_messages[] = {
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

static const char * selectors[] = {
    "NULL",
    "Kernel Code",
    "Kernel Data",
    "User Code",
    "User Data",
    "TSS"
};
#define selector_count 6

void x86_interrupt_handler(x86_interrupt_t stack_frame) {
    transitional_panic_paint();

    u4 ec = stack_frame.error_code;

    print_string(
"==============================<!>Kernel Panic<!>==============================\n"
"The system has encountered an unrecoverable "
); print_string(panic_message ?
    "software error:\n" : "unhandled hardware exception:\n");
print_string(
"  Interrupt Number: "); print_uint(stack_frame.idt_index); print_string("\n"
"  Error Code: "); print_uint(ec);
print_string("\n  Message: ");
    if (panic_message) {
        print_string(panic_message);
    } else {
        if (stack_frame.idt_index < 32) {
            print_string(x86_interrupt_messages[stack_frame.idt_index]);
            if (stack_frame.idt_index == 13) { // GPF
                if (ec & 1)
                    print_string(" Externally");
                print_string(" Caused By ");
                const char * tables[] = { "GDT", "IDT", "LDT", "IDT" };
                u1 table = (ec >> 1) & 3;
                print_string(tables[table]);
                print_char('[');
                u4 index = (ec >> 3) & 8191;
                print_uint(index);
                print_char(']');
                if (table == 0) {
                    print_string(" (");
                    print_string((index >= selector_count) ?
                        "Invalid Selector" : selectors[index]);
                    print_char(')');
                } else if (table & 1) { // IDT Helper
                    print_string(" (");
                    if (index < 32) {
                        print_string(x86_interrupt_messages[index]);
                    } else {
                        print_string("IRQ");
                        print_uint(index - 32);
                    }
                    print_char(')');
                }
            }
        } else {
            print_string("No message found for this exception");
        }
    }

    print_string("\n\n"
"--Registers-------------------------------------------------------------------\n"
"    EIP: "); print_hex(stack_frame.eip); print_string("\n"
"    EFLAGS: "); print_hex(stack_frame.eflags); print_string("\n"
"    EAX: "); print_hex(stack_frame.eax); print_string("\n"
"    ECX: "); print_hex(stack_frame.ecx); print_string("\n"
"    EDX: "); print_hex(stack_frame.edx); print_string("\n"
"    EBX: "); print_hex(stack_frame.ebx); print_string("\n"
"    ESP: "); print_hex(stack_frame.esp); print_string("\n"
"    EBP: "); print_hex(stack_frame.ebp); print_string("\n"
"    ESI: "); print_hex(stack_frame.esi); print_string("\n"
"    EDI: "); print_hex(stack_frame.edi); print_string("\n"
"    CS: "); print_hex(stack_frame.cs);
    print_string(" (");
    u4 selector_index = stack_frame.cs / 8;
    print_string((selector_index >= selector_count) ?
        "Invalid Selector" : selectors[selector_index]);
    print_string(")\n");

    disable_interrupts();
    halt();
}

