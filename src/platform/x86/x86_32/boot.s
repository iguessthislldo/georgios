/*
    xchg %bx, %bx
*/

/*
 * MULTIBOOT HEADER
 */

.set ALIGN,    1<<0             /* align loaded modules on page boundaries */
.set MEMINFO,  1<<1             /* provide memory map */
.set FLAGS,    ALIGN | MEMINFO  /* this is the Multiboot 'flag' field */
.set MAGIC,    0x1BADB002       /* 'magic number' lets bootloader find the header */
.set CHECKSUM, -(MAGIC + FLAGS) /* checksum of above, to prove we are multiboot */
.section .multiboot
.align 4
.long MAGIC
.long FLAGS
.long CHECKSUM

/*
 * STACK
 */

.section .bss
.align 16
stack_bottom:
.skip 16384 # 16 KiB
stack_top:

/*
 * PAGE DIRECTORY
 */
.section .bss
.global page_directory
.align 4096
page_directory:
.skip 4096

/*
 * KERNEL PAGE TABLE
 */
.global kernel_page_table
.align 4096
kernel_page_table:
.skip 4096

/*
 * GLOBAL DESCRIPTOR TABLE
 */

.section .text
.global gdt_load
.type gdt_load, @function
gdt_load:
    lgdt gdt_pointer
    movw $0x10, %ax
    movw %ax, %ds
    movw %ax, %es
    movw %ax, %fs
    movw %ax, %gs
    movw %ax, %ss
    jmp gdt_complete_load
gdt_complete_load:
    ret

// Context * setup_process(u4 eip, u4 esp)
.section .text
.global setup_process
.type setup_process, @function
setup_process:
    pushl %ebx // Save ebx

    // Get Values
    movl 8(%esp), %eax // eip
    movl 12(%esp), %ebx // esp
    pushf
    pop %ecx // eflags

    // Swap Out Stacks
    movl %esp, %edx
    movl %ebx, %esp

    // Create Inital Process Stack
    // for iret
    pushl %ecx // eflags
    pushl %cs // cs
    pushl %eax // eip
    // for popa
    pushl $0 // eax
    pushl $0 // ecx
    pushl $0 // edx
    pushl $0 // ebx
    pushl %ebx // esp
    pushl %ebx // ebp
    pushl $0 // esi
    pushl $0 // edi
    // for context_switch
    pushl $irq0_return
    pushl %ebx // ebp
    pushl $0 // ebx
    pushl $0 // esi
    pushl $0 // edi

    // Restore Stack
    movl %esp, %eax // Return Context
    movl %edx, %esp

    popl %ebx // Restore ebx
    ret

// void context_switch(Context ** old, Context * new);
.section .text
.global context_switch
.type context_switch, @function
context_switch:
    movl 4(%esp), %eax // old context
    movl 8(%esp), %edx // new context

    // Save old registers
    pushl %ebp
    pushl %ebx
    pushl %esi
    pushl %edi

    // Switch to new stack
    movl %esp, (%eax)
    movl %edx, %esp

    // Load new registers
    popl %edi
    popl %esi
    popl %ebx
    popl %ebp

    ret // Return to new context (hopefully)

/*
 * Entry
 */
.section .text
.global _start
.type _start, @function
_start:
    cli

    // Set up Double 1:1 paging for the first 4 MiB offset by KERNEL_OFFSET
    //   At 0 and KERNEL_OFFSET
    //   First put the physical location of the Kernel Page Table in the page
    //   directory:
    mov $kernel_page_table, %eax
    sub $KERNEL_OFFSET, %eax
    and $0xFFFFF000, %eax
    or $1, %eax
    mov $page_directory, %ebx
    sub $KERNEL_OFFSET, %ebx
    mov $0, %ecx
    mov %eax, (%ebx,%ecx)
    mov $KERNEL_OFFSET, %ecx
    shr $20, %ecx
    mov %eax, (%ebx,%ecx)
    //   Then fill kernel_page_table
    sub $1, %eax
    mov $0, %ebx
    mov $0x400, %ecx
    mov $1, %edx
    kernel_page_table_fill_loop:
    mov %edx, (%eax, %ebx, 4)
    add $0x1000, %edx
    add $1, %ebx
    cmp %ecx, %ebx
    jl kernel_page_table_fill_loop

    // Enable Paging
    mov $page_directory, %eax
    sub $KERNEL_OFFSET, %eax
    mov %eax, %cr3
    mov %cr0, %eax
    or $0x80000000, %eax
    mov %eax, %cr0

    // Jump to Higher Kernel
    movl $higher_kernel, %eax
    jmp %eax
higher_kernel:
    //   And Unmap kernel_page_table from 0x0
    movl $0, page_directory

    // Set Stack Location
    mov $stack_top, %esp

    // Rest of Platform Setup
    call platform_init

    // Start Main Part of Kernel
    call kernel_main

    // Loop
    cli
1:	hlt
    jmp 1b

