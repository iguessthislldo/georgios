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

pub const StringWriter = struct {
    const Writer = std.io.Writer(*StringWriter, std.mem.Allocator.Error, write);
    const String = std.ArrayList(u8);

    string: String,

    pub fn init(alloc: std.mem.Allocator) StringWriter {
        return .{.string = String.init(alloc)};
    }

    pub fn deinit(self: *StringWriter) void {
        self.string.deinit();
    }

    fn write(self: *StringWriter, bytes: []const u8) std.mem.Allocator.Error!usize {
        try self.string.appendSlice(bytes);
        return bytes.len;
    }

    pub fn writer(self: *StringWriter) Writer {
        return .{.context = self};
    }

    pub fn get(self: *StringWriter) []const u8 {
        return self.string.toOwnedSlice();
    }
};

test "StringWriter" {
    var ta = utils.TestAlloc{};
    defer ta.deinit(.Panic);
    errdefer ta.deinit(.NoPanic);
    const alloc = ta.alloc();

    var sw = StringWriter.init(alloc);

    const s1 = sw.get();
    try std.testing.expectEqualStrings("", s1);
    alloc.free(s1);

    try sw.writer().print("{} Hello {s}\n", .{1, "World"});
    try sw.writer().print("{} Hello {s}\n", .{2, "again"});
    const s2 = sw.get();
    try std.testing.expectEqualStrings(
        \\1 Hello World
        \\2 Hello again
        \\
        , s2);
    alloc.free(s2);

    const s3 = sw.get();
    try std.testing.expectEqualStrings("", s3);
    alloc.free(s3);

    ta.deinit(.Panic);
}

pub const StringReader = struct {
    const Error = error{};
    const Reader = std.io.Reader(*StringReader, Error, read);

    string: []const u8,
    pos: usize = 0,

    fn read(self: *StringReader, bytes: []u8) Error!usize {
        const len = utils.memory_copy_truncate(bytes, self.string[self.pos..]);
        self.pos += len;
        return len;
    }

    pub fn reader(self: *StringReader) Reader {
        return .{.context = self};
    }
};

test "StringReader" {
    var sr = StringReader{.string = "Hello World!"};
    var reader = sr.reader();

    var buffer: [6]u8 = undefined;
    try std.testing.expectEqualStrings("Hello ", buffer[0..try reader.read(buffer[0..])]);
    try std.testing.expectEqualStrings("World!", buffer[0..try reader.read(buffer[0..])]);
    try std.testing.expectEqualStrings("", buffer[0..try reader.read(buffer[0..])]);
}

fn fmt_dump_hex_impl(bytes: []const u8, comptime fmt: []const u8,
        options: std.fmt.FormatOptions, writer: anytype) !void {
    _ = fmt;
    _ = options;

    // Print hex data like this:
    //                        VV group_sep
    // 00 01 02 03 04 05 06 07  08 09 0A 0B 0C 0D 0E 0F
    // ^^ Byte ^ byte_sep  Group^^^^^^^^^^^^^^^^^^^^^^^
    const group_byte_count = 8;
    const byte_sep = " ";
    const group_size =
        group_byte_count * 2 + // Bytes
        ((group_byte_count * byte_sep.len) - 1); // byte_sep Between Bytes
    const group_count = 2;
    const group_sep = "  ";
    const buffer_size =
        group_size * group_count + // Groups
        (group_count - 1) * group_sep.len + // group_sep Between Groups
        1; // Newline

    var buffer: [buffer_size]u8 = undefined;
    var i: usize = 0;
    var buffer_pos: usize = 0;
    var byte_i: usize = 0;
    var group_i: usize = 0;
    var has_next = i < bytes.len;
    var print_buffer = false;
    while (has_next) {
        const next_i = i + 1;
        has_next = next_i < bytes.len;
        print_buffer = !has_next;
        {
            const new_pos = buffer_pos + 2;
            byte_buffer(buffer[buffer_pos..new_pos], bytes[i]);
            buffer_pos = new_pos;
        }
        byte_i += 1;
        if (byte_i == group_byte_count) {
            byte_i = 0;
            group_i += 1;
            if (group_i == group_count) {
                group_i = 0;
                print_buffer = true;
            } else {
                for (group_sep[0..group_sep.len]) |b| {
                    buffer[buffer_pos] = b;
                    buffer_pos += 1;
                }
            }
        } else if (has_next) {
            for (byte_sep[0..byte_sep.len]) |b| {
                buffer[buffer_pos] = b;
                buffer_pos += 1;
            }
        }
        if (print_buffer) {
            buffer[buffer_pos] = '\n';
            buffer_pos += 1;
            try writer.writeAll(buffer[0..buffer_pos]);
            buffer_pos = 0;
            print_buffer = false;
        }
        i = next_i;
    }
}

pub fn fmt_dump_hex(bytes: []const u8) std.fmt.Formatter(fmt_dump_hex_impl) {
    return .{.data = bytes};
}
