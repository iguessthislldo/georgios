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

    // Switch to new stack
    movl %esp, (%eax)
    movl %edx, %esp

    ret // Return to new context (hopefully)

// void usermode(mem_t ip, memt sp)
.section .text
.global usermode
.type usermode, @function
usermode:
    movl 4(%esp), %ecx // ip, Where to jump as ring 3
    movl 8(%esp), %edx // sp, What the stack should be

    // Load User Data Selector into Data Segment Registers
    movl (user_data_selector), %eax
    movw %ax, %ds
    movw %ax, %es
    movw %ax, %fs
    movw %ax, %gs

    // Push arguments for iret
    pushl %eax // ss
    pushl %edx // sp
    pushf // flags
    pushl (user_code_selector) // cs
    pushl %ecx // ip
    sti
    iret // jump to ip as ring 3

