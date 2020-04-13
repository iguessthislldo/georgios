// These are wrappers of what is in fprint.zig for convenience. See there for
// the implementations.

const builtin = @import("builtin");

const isspace = @import("util.zig").isspace;
const fprint = @import("fprint.zig");
const io = @import("io.zig");

var console_file: ?*io.File = null;

pub fn initialize(file: ?*io.File) void {
    console_file = file;
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
        fprint.stripped_string(o, str) catch unreachable;
    }
}

pub fn uint(value: usize) void {
    if (console_file) |o| {
        fprint.uint(o, value) catch unreachable;
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
