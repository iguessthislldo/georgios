// TODO: Remove this? Replace with std writers/formatters?

const std = @import("std");

const utils = @import("utils.zig");

pub const Error = utils.Error;
const ToString = @This();

buffer: ?[]u8 = null,
got: usize = 0,
ext_func: ?fn(self: *ToString, str: []const u8) void = null,
truncate: ?[]const u8 = null,

fn left(self: *const ToString) usize {
    if (self.buffer) |buf| {
        return buf.len - self.got;
    }
    return std.math.maxInt(usize);
}

pub fn need(self: *const ToString, space: usize) Error!void {
    if (self.truncate == null and space > self.left()) {
        return Error.NotEnoughDestination;
    }
}

pub fn get(self: *ToString) []u8 {
    if (self.buffer) |buf| {
        return buf[0..@minimum(buf.len, self.got)];
    }
    @panic("This ToString doesn't have a buffer set");
}

pub fn upgrade_buffer(self: *ToString, new: []u8) Error!?[]u8 {
    if (self.buffer) |buf| {
        _ = try utils.memory_copy_error(new, buf);
        self.buffer = new;
        return buf;
    }
    self.buffer = new;
    self.got = 0;
    return null;
}

fn _str(self: *ToString, s: []const u8) void {
    if (self.buffer) |buf| {
        if (self.left() == 0) {
            return;
        }
        var from = s;
        var i: usize = 0;
        var in_truncated = false;
        while (i < from.len) {
            if (self.got >= buf.len) {
                break;
            } else if (self.truncate) |truncate_end| {
                if (!in_truncated and self.left() == truncate_end.len) {
                    in_truncated = true;
                    from = truncate_end[0..];
                    continue;
                }
            }
            buf[self.got] = from[i];
            self.got += 1;
            i += 1;
        }
    }
    if (self.ext_func) |ef| {
        ef(self, s);
    }
}

fn _char(self: *ToString, c: u8) void {
    self._str(([_]u8{c})[0..]);
}

pub fn char(self: *ToString, c: u8) Error!void {
    try self.need(1);
    self._char(c);
}

pub fn string(self: *ToString, src: []const u8) Error!void {
    try self.need(src.len);
    self._str(src);
}

pub fn string_truncate(self: *ToString, src: []const u8) void {
    self._str(src[0..@minimum(src.len, self.left())]);
}

pub fn cstring(self: *ToString, cstr: [*:0]const u8) Error!void {
    try self.string(utils.cstring_to_string(cstr));
}

fn hex_recurse(self: *ToString, value: usize) void {
    const next = value / 0x10;
    if (next > 0) {
        self.hex_recurse(next);
    }
    self._char(utils.nibble_char(@intCast(u4, value % 0x10)));
}

pub fn hex(self: *ToString, value: usize) Error!void {
    try self.need(2 + utils.hex_char_len(usize, value));
    self._char('0');
    self._char('x');
    if (value == 0) {
        self._char('0');
        return;
    }
    self.hex_recurse(value);
}

fn _int_recurse(self: *ToString, sign: ?u8, needs: usize, value: anytype) Error!void {
    const next = value / 10;
    if (next > 0) {
        try self._int_recurse(sign, needs + 1, next);
    } else {
        const add: usize = if (sign != null) 1 else 0;
        try self.need(needs + add);
        if (sign) |s| self._char(s);
    }
    self._char('0' + @intCast(u8, value % 10));
}

pub fn _int(self: *ToString, value: anytype) Error!void {
    if (value == 0) {
        try self.char('0');
        return;
    }
    const signed = std.meta.trait.isSignedInt(@TypeOf(value));
    try self._int_recurse(if (signed and value < 0) '-' else null, 1,
        std.math.absCast(value));
}

pub fn int(self: *ToString, value: anytype) Error!void {
    const Type = @TypeOf(value);
    comptime std.debug.assert(@typeInfo(Type) == .Int);
    try self._int(value);
}

pub fn uint(self: *ToString, value: usize) Error!void {
    try self._int(value);
}

pub fn std_write(self: *ToString, bytes: []const u8) Error!usize {
    try self.string(bytes);
    return bytes.len;
}

pub const StdWriter = std.io.Writer(*ToString, Error, std_write);

pub fn std_writer(self: *ToString) StdWriter {
    return StdWriter{.context = self};
}

test "ToString" {
    {
        var buffer: [128]u8 = undefined;
        var ts = ToString{.buffer = buffer[0..]};
        try ts.string("Hello ");
        try ts.string("");
        try ts.cstring("goodbye!");
        try ts.cstring("");
        try std.testing.expectEqualStrings("Hello goodbye!", ts.get());
    }
    {
        var buffer: [1]u8 = undefined;
        var ts = ToString{.buffer = buffer[0..]};
        try std.testing.expectError(Error.NotEnoughDestination, ts.string("Hello"));
        try std.testing.expectEqualStrings("", ts.get());
    }
    {
        var buffer: [128]u8 = undefined;
        var ts = ToString{.buffer = buffer[0..]};
        try ts.hex(0x0);
        try ts.hex(0x1);
        try ts.hex(0xf);
        try ts.hex(0x10);
        try ts.hex(0xff);
        try ts.hex(0x100);
        try std.testing.expectEqualStrings("0x00x10xf0x100xff0x100", ts.get());
    }
    {
        var buffer: [1]u8 = undefined;
        var ts = ToString{.buffer = buffer[0..]};
        try std.testing.expectError(Error.NotEnoughDestination, ts.hex(0xff));
        try std.testing.expectEqualStrings("", ts.get());
    }
    {
        var buffer: [10]u8 = undefined;
        var ts = ToString{.buffer = buffer[0..]};
        try ts.uint(10); // 2
        try ts.uint(1234); // 6
        try std.testing.expectError(Error.NotEnoughDestination, ts.uint(56789)); // 11
        try ts.uint(5678); // 10
        try std.testing.expectEqualStrings("1012345678", ts.get());
    }
    {
        var buffer: [10]u8 = undefined;
        var ts = ToString{.buffer = buffer[0..], .truncate = ".."};
        try ts.uint(10);
        try ts.uint(1234);
        try std.testing.expectEqualStrings("101234", ts.get());
        try ts.uint(56789);
        try std.testing.expectEqualStrings("10123456..", ts.get());
        try ts.string("another thing");
        try std.testing.expectEqualStrings("10123456..", ts.get());
    }
    {
        var buffer: [10]u8 = undefined;
        var ts = ToString{.buffer = buffer[0..]};
        try ts.std_writer().print("0o{o}", .{0o123});
        try std.testing.expectEqualStrings("0o123", ts.get());
    }
}
