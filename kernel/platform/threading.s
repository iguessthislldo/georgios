// mem_t setup_process(bool usermode, mem_t eip, mem_t esp)
.section .text
.global setup_process
.type setup_process, @function
setup_process:
    pushl %ebx // Save ebx
    pushl %esi // Save esi

    // Get Values
    movl 8(%esp), %esi // usermode
    movl 12(%esp), %eax // eip
    movl 16(%esp), %ebx // esp
    pushf
    pop %ecx // eflags

    // Swap Out Stacks
    movl %esp, %edx
    movl %ebx, %esp

    // Create Inital Process Stack
    // for iret
    cmp %eax, 0
    je setup_process_kernel_mode // Skip Pushing these if Going to Kernel Mode
    pushl $0x23 // ss (user data selector)
    pushl %ebx // esp
  setup_process_kernel_mode:
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

    // Restore Stack
    movl %esp, %eax // Return Context
    movl %edx, %esp

    popl %esi // Restore esi
    popl %ebx // Restore ebx
    ret

// void context_switch(mem_t * old, mem_t new);
.section .text
.global context_switch
.type context_switch, @function
context_switch:
    movl 4(%esp), %eax // pointer to old context location
    movl 8(%esp), %edx // new context location

    // Switch to new stack
    movl %esp, (%eax)
    movl %edx, %esp

    ret // Return to new context (hopefully)

// void usermode(mem_t ip, memt sp)
.section .text
.global usermode
.type usermode, @function
usermode:
    movl 4(%esp), %eax // ip, Where to jump as ring 3
    movl 8(%esp), %ebx // sp, What the stack should be

    // Get the User Data and Code Selectors
/*
    movl (user_data_selector), %edi
    movl (%edi), %edx
    movl (user_code_selector), %edi
    movl (%edi), %ecx
*/
    movl $0x23, %edx
    movl $0x1b, %ecx

    // Load User Data Selector into Data Segment Registers
    movw %dx, %ds
    movw %dx, %es
    movw %dx, %fs
    movw %dx, %gs

    // Push arguments for iret
    pushl %edx // ss
    pushl %ebx // sp
    pushf // flags
    pushl %ecx // cs
    pushl %eax // ip
    sti
    iret // jump to ip as ring 3

