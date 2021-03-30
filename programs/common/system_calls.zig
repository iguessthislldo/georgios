const util = @import("util.zig");

pub fn print_string(s: []const u8) callconv(.Inline) void {
    asm volatile ("int $100" ::
        [syscall_number] "{eax}" (@as(u32, 0)), [arg1] "{ebx}" (@ptrToInt(&s)));
}

pub fn getc() callconv(.Inline) u8 {
    var c: u8 = undefined;
    asm volatile ("int $100" ::
        [syscall_number] "{eax}" (@as(u32, 1)), [arg1] "{ebx}" (@ptrToInt(&c)));
    return c;
}

pub fn yield() callconv(.Inline) void {
    asm volatile ("int $100" :: [syscall_number] "{eax}" (@as(u32, 2)));
}

pub fn exit(status: u8) callconv(.Inline) void {
    asm volatile ("int $100" ::
        [syscall_number] "{eax}" (@as(u32, 3)), [arg1] "{ebx}" (status));
}

pub fn exec(path: []const u8) callconv(.Inline) bool {
    var failure: bool = undefined;
    asm volatile ("int $100" ::
        [syscall_number] "{eax}" (@as(u32, 4)),
        [arg1] "{ebx}" (@ptrToInt(&path)),
        [arg2] "{ecx}" (@ptrToInt(&failure)));
    return failure;
}

pub fn get_key() callconv(.Inline) util.Key {
    var key: util.Key  = undefined;
    asm volatile ("int $100" ::
        [syscall_number] "{eax}" (@as(u32, 5)), [arg1] "{ebx}" (@ptrToInt(&key)));
    return key;
}
