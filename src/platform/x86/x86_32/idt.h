#ifndef X86_IDT_HEADER
#define X86_IDT_HEADER

#include <library.h>

/* 
 * Interrupt Descriptor Table
 */

#define IDT_SIZE 256

// Entries
struct idt_entry_struct {
	u2 base_low;
	u2 select;
	u1 zero;
	u1 flags;
    u2 base_high;
} __attribute__((packed));
typedef struct idt_entry_struct idt_entry_t;

// Pointer
struct idt_pointer_struct {
	u2 limit;
	u4 base;
} __attribute__((packed));
typedef struct idt_pointer_struct idt_pointer_t;

// Values
idt_entry_t idt[IDT_SIZE];
idt_pointer_t idt_pointer;

// Functions
#define idt_load() asm volatile ("lidt (%0)" : : "r" (&idt_pointer))
void idt_set(u1 index, u4 base, u2 select, u1 flags);
void idt_initialize();
void idt_set_handler(u1 index, void (*handler)());

// x86 Exception Handlers
extern void ih_0();
extern void ih_1();
extern void ih_2();
extern void ih_3();
extern void ih_4();
extern void ih_5();
extern void ih_6();
extern void ih_7();
extern void ih_8();
extern void ih_9();
extern void ih_10();
extern void ih_11();
extern void ih_12();
extern void ih_13();
extern void ih_14();
extern void ih_15();
extern void ih_16();
extern void ih_17();
extern void ih_18();
extern void ih_19();
extern void ih_20();
extern void ih_21();
extern void ih_22();
extern void ih_23();
extern void ih_24();
extern void ih_25();
extern void ih_26();
extern void ih_27();
extern void ih_28();
extern void ih_29();
extern void ih_30();
extern void ih_31();
extern void ih_pic();

struct x86_exception_struct {
   u4 ss, gs, fs, es, ds; // Pushed
/*
   u4 edi, esi, ebp, esp, ebx, edx, ecx, eax; // Pushed by us using pusha
*/
   u4 idt_index; // Pushed by us
   u4 error_code; // Pushed by us if the CPU didn't push one
/*
   // Pushed by the processor automatically
   u4 eip, cs, eflags, old_esp, old_ss;
*/
} __attribute__((packed));
typedef struct x86_exception_struct x86_exception_t;

//void x86_exception_handler(x86_exception_t e);
void x86_exception_handler(
   u4 ss, u4 gs, u4 fs, u4 es, u4 ds, u4 idt_index, u4 error_code
);

#endif
