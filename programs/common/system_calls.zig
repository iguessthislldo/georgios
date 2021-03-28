const util = @import("util.zig");

pub inline fn print_string(s: []const u8) void {
    asm volatile ("int $100" ::
        [syscall_number] "{eax}" (@as(u32, 0)), [arg1] "{ebx}" (@ptrToInt(&s)));
}

pub inline fn getc() u8 {
    var c: u8 = undefined;
    asm volatile ("int $100" ::
        [syscall_number] "{eax}" (@as(u32, 1)), [arg1] "{ebx}" (@ptrToInt(&c)));
    return c;
}

pub inline fn yield() void {
    asm volatile ("int $100" :: [syscall_number] "{eax}" (@as(u32, 2)));
}

pub inline fn exit(status: u8) void {
    asm volatile ("int $100" ::
        [syscall_number] "{eax}" (@as(u32, 3)), [arg1] "{ebx}" (status));
}

pub inline fn exec(path: []const u8) bool {
    var failure: bool = undefined;
    asm volatile ("int $100" ::
        [syscall_number] "{eax}" (@as(u32, 4)),
        [arg1] "{ebx}" (@ptrToInt(&path)),
        [arg2] "{ecx}" (@ptrToInt(&failure)));
    return failure;
}

pub inline fn get_key() util.Key {
    var key: util.Key  = undefined;
    asm volatile ("int $100" ::
        [syscall_number] "{eax}" (@as(u32, 5)), [arg1] "{ebx}" (@ptrToInt(&key)));
    return key;
}
