// These are wrappers of what is in fprint.zig for convenience. See there for
// the implementations.

const builtin = @import("builtin");

const isspace = @import("util.zig").isspace;
const fprint = @import("fprint.zig");
const io = @import("io.zig");

pub var console_file: ?*io.File = null;
pub var debug_print = false;

pub fn initialize(file: ?*io.File, debug: bool) void {
    console_file = file;
    debug_print = debug;
}

pub fn get_console_file() ?*io.File {
    return console_file;
}

pub fn char(ch: u8) void {
    if (console_file) |o| {
        fprint.char(o, ch) catch unreachable;
    }
}

pub fn nstring(str: [*]const u8, size: usize) void {
    if (console_file) |o| {
        fprint.nstring(o, str, size) catch unreachable;
    }
}

pub fn string(str: []const u8) void {
    if (console_file) |o| {
        fprint.string(o, str) catch unreachable;
    }
}

pub fn cstring(str: [*]const u8) void {
    if (console_file) |o| {
        fprint.cstring(o, str) catch unreachable;
    }
}

pub fn stripped_string(str: [*]const u8, size: usize) void {
    if (console_file) |o| {
        fprint.stripped_string(o, str, size) catch unreachable;
    }
}

pub fn uint(value: usize) void {
    if (console_file) |o| {
        fprint.uint(o, value) catch unreachable;
    }
}

pub fn uint64(value: u64) void {
    if (console_file) |o| {
        fprint.uint64(o, value) catch unreachable;
    }
}

pub fn int(value: isize) void {
    if (console_file) |o| {
        fprint.int(o, value) catch unreachable;
    }
}

pub fn int_sign(value: usize, show_positive: bool) void {
    if (console_file) |o| {
        fprint.int_sign(o, value) catch unreachable;
    }
}

pub fn hex(value: usize) void {
    if (console_file) |o| {
        fprint.hex(o, value) catch unreachable;
    }
}

pub fn address(value: usize) void {
    if (console_file) |o| {
        fprint.address(o, value) catch unreachable;
    }
}

pub fn byte(value: u8) void {
    if (console_file) |o| {
        fprint.byte(o, value) catch unreachable;
    }
}

pub fn boolean(value: bool) void {
    if (console_file) |o| {
        fprint.boolean(o, value) catch unreachable;
    }
}

pub fn any(value: var) void {
    if (console_file) |o| {
        fprint.any(o, value) catch unreachable;
    }
}

pub fn format(comptime fmtstr: []const u8, args: ...) void {
    if (console_file) |o| {
        fprint.format(o, fmtstr, args) catch unreachable;
    }
}

pub fn data(ptr: usize, size: usize) void {
    if (console_file) |o| {
        fprint.data(o, ptr, size) catch unreachable;
    }
}

pub fn data_bytes(byteslice: []u8) void {
    if (console_file) |o| {
        fprint.data_bytes(o, byteslice) catch unreachable;
    }
}

pub fn bytes(comptime Type: type, value: *Type) void {
    if (console_file) |o| {
        fprint.bytes(o, Type, value) catch unreachable;
    }
}

// void print_data(u1 * ptr, u4 size);

// size_t sprint_uint(u4 value, char * output);

// size_t sprint_size(mem_t size, char * buffer, size_t buffer_size);

// print.string("0x0 -> ");
// print.hex(0x0);
// print.char('\n');
// print.string("0x1 -> ");
// print.hex(0x1);
// print.char('\n');
// print.string("0x9 -> ");
// print.hex(0x9);
// print.char('\n');
// print.string("0xA -> ");
// print.hex(0xA);
// print.char('\n');
// print.string("0xF -> ");
// print.hex(0xF);
// print.char('\n');
// print.string("0x10 -> ");
// print.hex(0x10);
// print.char('\n');
// print.string("0xABCDEF -> ");
// print.hex(0xABCDEF);
// print.char('\n');

// print.byte(0x00);
// print.char('\n');
// print.byte(0x01);
// print.char('\n');
// print.byte(0x0F);
// print.char('\n');
// print.byte(0xFF);
// print.char('\n');

// var b: bool = false;
// var x: u16 = 0xABCD;
// print.format("Hello {} {}\n", @intCast(usize, 10), b);
// print.format("Strings {} {}\n", "Hello1", c"Hello2");
// print.format("{{These braces are escaped}}\n");
// print.format("{:x}\n", x);

pub fn debug_char(ch: u8) void {
    if (debug_print) {
        char(ch);
    }
}

pub fn debug_nstring(str: [*]const u8, size: usize) void {
    if (debug_print) {
        nstring(str, size);
    }
}

pub fn debug_string(str: []const u8) void {
    if (debug_print) {
        string(str);
    }
}

pub fn debug_cstring(str: [*]const u8) void {
    if (debug_print) {
        cstring(str);
    }
}

pub fn debug_stripped_string(str: [*]const u8, size: usize) void {
    if (debug_print) {
        stripped_string(str);
    }
}

pub fn debug_uint(value: usize) void {
    if (debug_print) {
        uint(value);
    }
}

pub fn debug_uint64(value: u64) void {
    if (debug_print) {
        uint64(value);
    }
}

pub fn debug_int(value: isize) void {
    if (debug_print) {
        int(value);
    }
}

pub fn debug_int_sign(value: usize, show_positive: bool) void {
    if (debug_print) {
        int_sign(value, show_positive);
    }
}

pub fn debug_hex(value: usize) void {
    if (debug_print) {
        hex(value);
    }
}

pub fn debug_address(value: usize) void {
    if (debug_print) {
        address(value);
    }
}

pub fn debug_byte(value: u8) void {
    if (debug_print) {
        byte(value);
    }
}

pub fn debug_boolean(value: bool) void {
    if (debug_print) {
        boolean(value);
    }
}

pub fn debug_any(value: var) void {
    if (debug_print) {
        any(value);
    }
}

pub fn debug_format(comptime fmtstr: []const u8, args: ...) void {
    if (debug_print) {
        format(fmtstr, args);
    }
}

pub fn debug_data(ptr: usize, size: usize) void {
    if (debug_print) {
        data(ptr, size);
    }
}

pub fn debug_data_bytes(byteslice: []u8) void {
    if (debug_print) {
        data_bytes(byteslice);
    }
}

pub fn debug_bytes(comptime Type: type, value: *Type) void {
    if (debug_print) {
        bytes(Type, value);
    }
}
