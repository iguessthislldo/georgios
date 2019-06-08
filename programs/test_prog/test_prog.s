.section .text
.global test_prog_start
.type test_prog_start, @function
test_prog_start:
    movl $99, %eax // print_char
    movl $0x2B, %ebx // '+'
    int $100
    movl $test_prog_start, %eax
    jmp * %eax
