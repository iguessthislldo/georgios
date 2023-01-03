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

pub const DumpHexOptions = struct {
    // Print hex data like this:
    //                        VV group_sep
    // 00 01 02 03 04 05 06 07  08 09 0a 0b 0c 0d 0e 0f
    // ^^ Byte ^ byte_sep  Group^^^^^^^^^^^^^^^^^^^^^^^

    byte_sep: []const u8 = " ",
    group_byte_count: usize = 8,
    group_count: usize = 2,
    group_sep: []const u8 = "  ",
    line_end: []const u8 = "\n",
    compare_to: ?[]const u8 = null,
};

fn dump_hex_byte_count(bytes: []const u8, opts: DumpHexOptions, n: usize) usize {
    return @minimum(opts.group_byte_count * n, bytes.len);
}

fn dump_hex_group(bytes: []const u8, writer: anytype, opts: DumpHexOptions) !usize {
    var wrote: usize = 0;
    if (bytes.len > 0) {
        const last = bytes.len - 1;
        for (bytes) |byte, i| {
            var buffer: [2]u8 = undefined;
            byte_buffer(buffer[0..], byte);
            wrote += try writer.write(buffer[0..]);
            if (i != last) {
                wrote += try writer.write(opts.byte_sep);
            }
        }
    }
    return wrote;
}

fn dump_hex_line(bytes: []const u8, writer: anytype, opts: DumpHexOptions) !usize {
    var left = bytes;
    var wrote: usize = 0;
    if (bytes.len > 0) {
        const last = opts.group_count - 1;
        var i: usize = 0;
        while (i < opts.group_count and left.len > 0) {
            const byte_count = dump_hex_byte_count(left, opts, 1);
            const group = left[0..byte_count];
            wrote += try dump_hex_group(group, writer, opts);
            left = left[byte_count..];
            if (i < last and left.len > 0) {
                wrote += try writer.write(opts.group_sep);
            }
            i += 1;
        }
    }
    return wrote;
}

pub fn dump_hex(bytes: []const u8, writer: anytype, opts: DumpHexOptions) !void {
    var left = bytes;
    var compare_to_left = opts.compare_to orelse utils.empty_slice(u8, bytes.ptr);
    // Should be same length
    const same_sep = " == ";
    const not_same_sep = " != ";
    const group_size =
        opts.group_byte_count * 2 + // Bytes
        ((opts.group_byte_count * opts.byte_sep.len) - 1); // byte_sep Between Bytes
    const line_size =
        group_size * opts.group_count + // Groups
        (opts.group_count - 1) * opts.group_sep.len; // group_sep Between Groups
    while (left.len > 0 or compare_to_left.len > 0) {
        const byte_count = dump_hex_byte_count(left, opts, opts.group_count);
        const line = left[0..byte_count];
        left = left[byte_count..];
        const wrote = try dump_hex_line(line, writer, opts);
        if (opts.compare_to != null) {
            try writer.writeByteNTimes(' ', line_size - wrote);
            const ct_byte_count = dump_hex_byte_count(compare_to_left, opts, opts.group_count);
            const ct_line = compare_to_left[0..ct_byte_count];
            _ = try writer.write(
                if (utils.memory_compare(line, ct_line)) same_sep else not_same_sep);
            if (compare_to_left.len > 0) {
                _ = try dump_hex_line(ct_line, writer, opts);
                compare_to_left = compare_to_left[ct_byte_count..];
            }
        }
        _ = try writer.write(opts.line_end);
    }
}

test "dump_hex" {
    var ta = utils.TestAlloc{};
    defer ta.deinit(.Panic);
    errdefer ta.deinit(.NoPanic);
    const alloc = ta.alloc();

    var sw = StringWriter.init(alloc);
    var w = sw.writer();

    const bytes = [_]u8 {
        0x0, 0x1, 0x2, 0x3, 0x4, 0x5, 0x6, 0x7,
        0x8, 0x9, 0xa, 0xb, 0xc, 0xd, 0xe, 0xf,
        0xff,
    };

    {
        try dump_hex(bytes[0..0], w, .{});
        const s = sw.get();
        defer alloc.free(s);
        try std.testing.expectEqualStrings("", s);
    }

    {
        try dump_hex(bytes[0..1], w, .{});
        const s = sw.get();
        defer alloc.free(s);
        try std.testing.expectEqualStrings("00\n", s);
    }

    {
        try dump_hex(bytes[0..8], w, .{});
        const s = sw.get();
        defer alloc.free(s);
        try std.testing.expectEqualStrings("00 01 02 03 04 05 06 07\n", s);
    }

    {
        try dump_hex(bytes[0..9], w, .{});
        const s = sw.get();
        defer alloc.free(s);
        try std.testing.expectEqualStrings("00 01 02 03 04 05 06 07  08\n", s);
    }

    {
        try dump_hex(bytes[0..0x10], w, .{});
        const s = sw.get();
        defer alloc.free(s);
        try std.testing.expectEqualStrings(
            "00 01 02 03 04 05 06 07  08 09 0a 0b 0c 0d 0e 0f\n", s);
    }

    {
        try dump_hex(bytes[0..0x11], w, .{});
        const s = sw.get();
        defer alloc.free(s);
        try std.testing.expectEqualStrings(
            "00 01 02 03 04 05 06 07  08 09 0a 0b 0c 0d 0e 0f\nff\n", s);
    }

    {
        try dump_hex(bytes[0..0x10], w, .{.compare_to = bytes[0..8]});
        const s = sw.get();
        defer alloc.free(s);
        try std.testing.expectEqualStrings(
            "00 01 02 03 04 05 06 07  08 09 0a 0b 0c 0d 0e 0f != 00 01 02 03 04 05 06 07\n", s);
    }

    {
        try dump_hex(bytes[0..0x10], w, .{.compare_to = bytes[0..0x10]});
        const s = sw.get();
        defer alloc.free(s);
        try std.testing.expectEqualStrings(
            "00 01 02 03 04 05 06 07  08 09 0a 0b 0c 0d 0e 0f == " ++
            "00 01 02 03 04 05 06 07  08 09 0a 0b 0c 0d 0e 0f\n", s);
    }

    {
        try dump_hex(bytes[0..0x11], w, .{.compare_to = bytes[0..0x10]});
        const s = sw.get();
        defer alloc.free(s);
        try std.testing.expectEqualStrings(
            "00 01 02 03 04 05 06 07  08 09 0a 0b 0c 0d 0e 0f == " ++
            "00 01 02 03 04 05 06 07  08 09 0a 0b 0c 0d 0e 0f\n" ++
            "ff                                               != \n", s);
    }

    {
        try dump_hex(bytes[0..0x10], w, .{.compare_to = bytes[0..0x11]});
        const s = sw.get();
        defer alloc.free(s);
        try std.testing.expectEqualStrings(
            "00 01 02 03 04 05 06 07  08 09 0a 0b 0c 0d 0e 0f == " ++
            "00 01 02 03 04 05 06 07  08 09 0a 0b 0c 0d 0e 0f\n" ++
            "                                                 != ff\n", s);
    }

    {
        try dump_hex(bytes[0..0x11], w, .{.compare_to = bytes[0..0x11]});
        const s = sw.get();
        defer alloc.free(s);
        try std.testing.expectEqualStrings(
            "00 01 02 03 04 05 06 07  08 09 0a 0b 0c 0d 0e 0f == " ++
            "00 01 02 03 04 05 06 07  08 09 0a 0b 0c 0d 0e 0f\n" ++
            "ff                                               == ff\n", s);
    }

    {
        const a = [_]u8 {
            0x0, 0x1, 0x2, 0x3, 0x4, 0x5, 0x6, 0x7,
            0x8, 0x9, 0xa, 0xb, 0xc, 0xd, 0xe, 0xf,
            0xf0, 0x1, 0x2, 0x3, 0x4, 0x5, 0x6, 0x7, // <--
            0x8, 0x9, 0xa, 0xb, 0xc, 0xd, 0xe, 0xf,
            0x0, 0x1, 0x2, 0x3, 0x4, 0x5, 0x6, 0x7,
            0x8, 0x9, 0xa, 0xb, 0xc, 0xd, 0xe, 0xf,
        };
        const b = [_]u8 {
            0x0, 0x1, 0x2, 0x3, 0x4, 0x5, 0x6, 0x7,
            0x8, 0x9, 0xa, 0xb, 0xc, 0xd, 0xe, 0xf,
            0x0, 0x1, 0x2, 0x3, 0x4, 0x5, 0x6, 0x7,
            0x8, 0x9, 0xa, 0xb, 0xc, 0xd, 0xe, 0xf,
            0x0, 0x1, 0x2, 0x3, 0x4, 0x5, 0x6, 0x7,
            0x8, 0x9, 0xa, 0xb, 0xc, 0xd, 0xe, 0xf,
        };
        try dump_hex(a[0..], w, .{.compare_to = b[0..]});
        const s = sw.get();
        defer alloc.free(s);

        try std.testing.expectEqualStrings(
            "00 01 02 03 04 05 06 07  08 09 0a 0b 0c 0d 0e 0f == " ++
                "00 01 02 03 04 05 06 07  08 09 0a 0b 0c 0d 0e 0f\n" ++
            "f0 01 02 03 04 05 06 07  08 09 0a 0b 0c 0d 0e 0f != " ++
                "00 01 02 03 04 05 06 07  08 09 0a 0b 0c 0d 0e 0f\n" ++
            "00 01 02 03 04 05 06 07  08 09 0a 0b 0c 0d 0e 0f == " ++
                "00 01 02 03 04 05 06 07  08 09 0a 0b 0c 0d 0e 0f\n", s);
    }

    ta.deinit(.Panic);
}

fn fmt_dump_hex_impl(bytes: []const u8, comptime fmt: []const u8,
        options: std.fmt.FormatOptions, writer: anytype) !void {
    _ = fmt;
    _ = options;
    try dump_hex(bytes, writer, .{});
}

pub fn fmt_dump_hex(bytes: []const u8) std.fmt.Formatter(fmt_dump_hex_impl) {
    return .{.data = bytes};
}

const FmtCompareBytesData = struct {
    expected: []const u8,
    actual: []const u8,
};

fn fmt_compare_bytes_impl(data: FmtCompareBytesData, comptime fmt: []const u8,
        options: std.fmt.FormatOptions, writer: anytype) !void {
    _ = fmt;
    _ = options;
    try dump_hex(data.expected, writer, .{.compare_to = data.actual, .group_byte_count = 4});
}

pub fn fmt_compare_bytes(
        expected: []const u8, actual: []const u8) std.fmt.Formatter(fmt_compare_bytes_impl) {
    return .{.data = .{.expected = expected, .actual = actual}};
}

pub fn expect_equal_bytes(expected: []const u8, actual: []const u8) !void {
    if (!utils.memory_compare(expected, actual)) {
        std.debug.print("Expected the left side, but got the right:\n{}",
            .{fmt_compare_bytes(expected, actual)});
        return error.TestExpectedEqual;
    }
}
