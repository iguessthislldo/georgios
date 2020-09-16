pub inline fn print_char(c: u8) void {
    asm volatile ("int $100" ::
        [syscall_number] "{eax}" (u32(99)), [arg1] "{ebx}" (u32(c)));
}
