const std = @import("std");

const utils = @import("utils.zig");

pub fn isspace(c: u8) bool {
    return c == ' ' or c == '\n' or c == '\t' or c == '\r';
}

pub fn stripped_string_size(str: []const u8) callconv(.Inline) usize {
    var stripped_size: usize = 0;
    for (str) |c, i| {
        if (!isspace(c)) stripped_size = i + 1;
    }
    return stripped_size;
}

pub fn string_length(bytes: []const u8) callconv(.Inline) usize {
    for (bytes[0..]) |*ptr, i| {
        if (ptr.* == 0) {
            return i;
        }
    }
    return bytes.len;
}

pub fn cstring_length(cstr: [*:0]const u8) usize {
    var i: usize = 0;
    while (cstr[i] != 0) {
        i += 1;
    }
    return i;
}

pub fn cstring_to_slice(cstr: [*:0]const u8) []const u8 {
    return @ptrCast([*]const u8, cstr)[0..cstring_length(cstr) + 1];
}

pub fn cstring_to_string(cstr: [*:0]const u8) []const u8 {
    return @ptrCast([*]const u8, cstr)[0..cstring_length(cstr)];
}

pub fn hex_char_len(comptime Type: type, value: Type) Type {
    if (value == 0) {
        return 1;
    }
    return utils.int_log2(Type, value) / 4 + 1;
}

fn test_hex_char_len(value: usize, expected: usize) !void {
    try std.testing.expectEqual(expected, hex_char_len(usize, value));
}

test "hex_char_len" {
    try test_hex_char_len(0x0, 1);
    try test_hex_char_len(0x1, 1);
    try test_hex_char_len(0xf, 1);
    try test_hex_char_len(0x10, 2);
    try test_hex_char_len(0x11, 2);
    try test_hex_char_len(0xff, 2);
    try test_hex_char_len(0x100, 3);
    try test_hex_char_len(0x101, 3);
}

pub fn nibble_char(value: u4) u8 {
    return
        if (value < 10)
            '0' + @intCast(u8, value)
        else
            'a' + @intCast(u8, value - 10);
}

/// Insert a hex byte to into a buffer.
pub fn byte_buffer(buffer: []u8, value: u8) void {
    buffer[0] = nibble_char(@intCast(u4, value >> 4));
    buffer[1] = nibble_char(@intCast(u4, value % 0x10));
}

pub fn starts_with(what: []const u8, prefix: []const u8) bool {
    if (what.len < prefix.len) return false;
    for (what[0..prefix.len]) |value, i| {
        if (value != prefix[i]) return false;
    }
    return true;
}

pub fn ends_with(what: []const u8, postfix: []const u8) bool {
    if (what.len < postfix.len) return false;
    for (what[what.len - postfix.len..]) |value, i| {
        if (value != postfix[i]) return false;
    }
    return true;
}
