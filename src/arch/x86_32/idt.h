#ifndef X86_IDT_HEADER
#define X86_IDT_HEADER

#include <library.h>

/* 
 * Interrupt Descriptor Table
 */

#define IDT_SIZE 256

#define halt() __asm__ ("cli;hlt\n\t");

// Entries
struct idt_entry_struct {
	u16 base_low;
	u16 select;
	u8 zero;
	u8 flags;
    u16 base_high;
} __attribute__((packed));
typedef struct idt_entry_struct idt_entry_t;

// Pointer
struct idt_pointer_struct {
	u16 limit;
	u32 base;
} __attribute__((packed));
typedef struct idt_pointer_struct idt_pointer_t;

// Values
idt_entry_t idt[IDT_SIZE];
idt_pointer_t idt_pointer;

// Functions
extern void idt_load();
void idt_set(u8 index, u32 base, u16 select, u8 flags);
void idt_initialize();

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

typedef struct x86_exception_struct {
   u32 ss, gs, fs, es, ds; // Pushed
/*
   u32 edi, esi, ebp, esp, ebx, edx, ecx, eax; // Pushed by us using pusha
*/
   u32 idt_index; // Pushed by us
   u32 error_code; // Pushed by us if the CPU didn't push one
/*
   // Pushed by the processor automatically
   u32 eip, cs, eflags, old_esp, old_ss;
*/
} __attribute__((packed));
typedef struct x86_exception_struct x86_exception_t;

void x86_exception_handler(x86_exception_t e);

#endif
