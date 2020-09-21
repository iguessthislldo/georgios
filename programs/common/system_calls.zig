pub inline fn print_string(s: []const u8) void {
    asm volatile ("int $100" ::
        [syscall_number] "{eax}" (u32(0)), [arg1] "{ebx}" (@ptrToInt(&s)));
}

pub inline fn getc() u8 {
    var c: u8 = undefined;
    asm volatile ("int $100" ::
        [syscall_number] "{eax}" (u32(1)), [arg1] "{ebx}" (@ptrToInt(&c)));
    return c;
}
