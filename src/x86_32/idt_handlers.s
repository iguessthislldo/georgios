.section .text
ih_common:
    //xchgw %bx, %bx
    // Push General Registers
    pushal // Push EAX, ECX, EDX, EBX, original ESP, EBP, ESI, and EDI

    /*
    // Push Segments
    pushl %ds
    pushl %es
    pushl %fs
    pushl %gs
    pushl %ss
    movw $0x10, %ax
    movw %ax, %ds
    movw %ax, %es
    movw %ax, %fs
    movw %ax, %gs
    movw %ax, %ss
    */

    // The stack should now be equivalent to x86_exception_t
    call x86_exception_handler

    /*
    addl $4, %esp
    popl    %gs
    popl    %fs
    popl    %es
    popl    %ds
    */
    popal
    addl $8, %esp
    
    iret 

.macro IH_NO_CODE value
.global ih_\value
.type ih_\value, @function
ih_\value:
    cli
    pushl 0
    pushl \value
    jmp ih_common
.endm

.macro IH_CODE value
.global ih_\value
.type ih_\value, @function
ih_\value:
    cli
    pushl \value
    jmp ih_common
.endm

IH_NO_CODE 0 
IH_NO_CODE 1 
IH_NO_CODE 2 
IH_NO_CODE 3 
IH_NO_CODE 4 
IH_NO_CODE 5 
IH_NO_CODE 6 
IH_NO_CODE 7 
IH_CODE 8 
IH_NO_CODE 9 
IH_CODE 10
IH_CODE 11
IH_CODE 12
IH_CODE 13
IH_CODE 14
IH_NO_CODE 15
IH_NO_CODE 16
IH_NO_CODE 17
IH_NO_CODE 18
IH_NO_CODE 19
IH_NO_CODE 20
IH_NO_CODE 21
IH_NO_CODE 22
IH_NO_CODE 23
IH_NO_CODE 24
IH_NO_CODE 25
IH_NO_CODE 26
IH_NO_CODE 27
IH_NO_CODE 28
IH_NO_CODE 29
IH_NO_CODE 30
IH_NO_CODE 31

