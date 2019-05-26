/*
    xchg %bx, %bx
*/

/*
 * MULTIBOOT2 HEADER
 */

#define ASM_FILE
#include "multiboot2.h"
#undef ASM_FILE

.section .multiboot
.align 8
multiboot_header_start:
.long MULTIBOOT2_HEADER_MAGIC
.long MULTIBOOT_ARCHITECTURE_I386
.long multiboot_header_end - multiboot_header_start
.long -(MULTIBOOT2_HEADER_MAGIC + MULTIBOOT_ARCHITECTURE_I386 + (multiboot_header_end - multiboot_header_start))
/*
multiboot_fb_tag_start:
.short MULTIBOOT_HEADER_TAG_FRAMEBUFFER
.short MULTIBOOT_HEADER_TAG_OPTIONAL
.long multiboot_fb_tag_end - multiboot_fb_tag_start
.long 1024
.long 768
.long 32
multiboot_fb_tag_end:
*/
.short MULTIBOOT_HEADER_TAG_END
.short 0
.long 8
multiboot_header_end:

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
 * TEMP PAGE TABLE
 */
.global temp_page_table
.align 4096
temp_page_table:
.skip 4096

/*
 * GLOBAL DESCRIPTOR TABLE
 */
.section .text
.global gdt_load
.type gdt_load, @function
gdt_load:
    lgdt gdt_pointer
    movw (kernel_data_selector), %ax
    movw %ax, %ds
    movw %ax, %es
    movw %ax, %fs
    movw %ax, %gs
    movw %ax, %ss
    jmp gdt_complete_load
  gdt_complete_load:
    movw (tss_selector), %ax
    ltr %ax
    ret

// bool attempt_lock(lock_t * lock)
.section .text
.global attempt_lock
.type attempt_lock, @function
attempt_lock:
    movl 4(%esp), %ecx // ecx = lock
    movl (%ecx), %eax // eax = *lock

    // Don't try if already locked
    testl %eax, %eax
    jnz attempt_lock_failed

    movl $1, %edx // edx = LOCKED

    // (Atomically)
    // if (*lock == eax) {
    //     *lock = LOCKED
    // } else { // Failed
    //     eax = LOCKED
    // }
    lock cmpxchgl %edx, (%ecx)

    // See if we succeeded
    testl %eax, %eax
    jnz attempt_lock_failed

    // Return Success
    movl $0, %eax
    ret

  attempt_lock_failed:
    // Return Failure
    movl $1, %eax
    ret

/*
 * Entry
 */
.section .text
.global _start
.type _start, @function
_start:
    cli

    // Push Multiboot struct pointer on to the future kernel stack
    mov $stack_top, %eax
    sub $_KERNEL_OFFSET, %eax // translate stack into a lower kernel address
    sub $4, %eax
    add $_KERNEL_OFFSET, %ebx // translate pointer to higher kernel address
    // Put higher address of Multiboot pointer in the first
    // 4 bytes of the stack
    mov %ebx, (%eax)

    // Set up Double 1:1 paging for the first 4 MiB offset by KERNEL_OFFSET
    //   At 0 and KERNEL_OFFSET
    //   First put the physical location of the Kernel Page Table in the page
    //   directory:
    mov $kernel_page_table, %eax
    sub $_KERNEL_OFFSET, %eax
    and $0xFFFFF000, %eax
    or $1, %eax
    mov $page_directory, %ebx
    sub $_KERNEL_OFFSET, %ebx
    mov $0, %ecx
    mov %eax, (%ebx,%ecx)
    mov $_KERNEL_OFFSET, %ecx
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
    sub $_KERNEL_OFFSET, %eax
    mov %eax, %cr3
    mov %cr0, %eax
    or $0x80000000, %eax
    mov %eax, %cr0

    // Jump to Higher Kernel
    movl $higher_kernel, %eax
    jmp * %eax
  higher_kernel:
    //   And Unmap kernel_page_table from 0x0
    movl $0, page_directory

    // Set Stack Location
    mov $stack_top, %esp
    sub $4, %esp // Sub 4 bytes for Multiboot pointer

    // Rest of Platform Setup
    call platform_init

    // Start Main Part of Kernel
    call kernel_main

    // Loop
    cli
1:	hlt
    jmp 1b

