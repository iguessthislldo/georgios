.section .text
panic_common:
    //xchgw %bx, %bx
    // Push General Registers
    pushal // Push EAX, ECX, EDX, EBX, original ESP, EBP, ESI, and EDI

    // The stack should now be equivalent to PanicStack
    mov %esp, panic_stack

    call show_panic_message

    popal // Restore Registers
    addl $8, %esp // Error Code
    iret

.macro IH_NO_CODE value
.global ih_\value
.type ih_\value, @function
ih_\value:
    //xchgw %bx, %bx
    cli
    pushl $0
    pushl $\value
    jmp panic_common
.endm

.macro IH_CODE value
.global ih_\value
.type ih_\value, @function
ih_\value:
    //xchgw %bx, %bx
    cli
    pushl $\value
    jmp panic_common
.endm

IH_NO_CODE 0  // Divide By Zero
IH_NO_CODE 1  // Debug
IH_NO_CODE 2  // Non-Maskable Interrupt
IH_NO_CODE 3  // Breakpoint
IH_NO_CODE 4  // Overflow
IH_NO_CODE 5  // Bound Range
IH_NO_CODE 6  // Invalid Opcode
IH_NO_CODE 7  // Device Not Available
IH_CODE 8     // Double Fault
IH_NO_CODE 9  // Coprocessor Seg Overrun
IH_CODE 10    // Invalid TSS
IH_CODE 11    // Missing Segment
IH_CODE 12    // Stack Segment Fault
IH_CODE 13    // Protection Fault
IH_CODE 14    // Page Fault
IH_NO_CODE 15 // Reserved
IH_NO_CODE 16 // Float Exception
IH_NO_CODE 17 // Alignment Check
IH_NO_CODE 18 // Machine Check
IH_NO_CODE 19 // SIMD
IH_NO_CODE 20 // Virtualiazation
IH_NO_CODE 21 // Reservered
IH_NO_CODE 22 // ...
IH_NO_CODE 23
IH_NO_CODE 24
IH_NO_CODE 25
IH_NO_CODE 26
IH_NO_CODE 27
IH_NO_CODE 28
IH_NO_CODE 29
IH_NO_CODE 30 // Security
IH_NO_CODE 31 // Reserved

.global ih_panic
.type ih_panic, @function
ih_panic:
    cli
    xchgw %bx, %bx
    pushl 12(%esp)
    pushl $50
    jmp panic_common

.global ih_system_call
// %eax is the call number
// %ebx is the argument
.type ih_system_call, @function
ih_system_call:
    cli
    pushal // Push EAX, ECX, EDX, EBX, original ESP, EBP, ESI, and EDI

    pushl %ebx // argument
    pushl %eax // call_number
    /* call system_call */
    popl %ecx
    popl %ecx

    popal // Restore Registers
    iret
