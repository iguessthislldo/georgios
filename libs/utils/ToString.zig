const std = @import("std");

const utils = @import("utils.zig");

pub const Error = utils.Error;
const ToString = @This();

buffer: []u8,
got: usize = 0,

pub fn need(self: *const ToString, space: usize) Error!void {
    if (space > (self.buffer.len - self.got)) {
        return Error.NotEnoughDestination;
    }
}

pub fn get(self: *ToString) []u8 {
    return self.buffer[0..self.got];
}

pub fn upgrade_buffer(self: *ToString, new: []u8) Error![]u8 {
    const old = self.buffer;
    _ = try utils.memory_copy_error(new, old);
    self.buffer = new;
    return old;
}

fn _char(self: *ToString, c: u8) void {
    self.buffer[self.got] = c;
    self.got += 1;
}

pub fn char(self: *ToString, c: u8) Error!void {
    try self.need(1);
    self._char(c);
}

pub fn string(self: *ToString, src: []const u8) Error!void {
    self.got += try utils.memory_copy_error(self.buffer[self.got..], src);
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

fn uint_recurse(self: *ToString, value: usize) Error!void {
    const next = value / 10;
    if (next > 0) {
        try self.uint_recurse(next);
    }
    try self.char('0' + @intCast(u8, value % 10));
}

pub fn uint(self: *ToString, value: usize) Error!void {
    if (value == 0) {
        try self.char('0');
        return;
    }
    const got = self.got;
    self.uint_recurse(value) catch |e| {
        // Restore
        self.got = got;
        return e;
    };
}

test "ToString" {
    {
        var buffer: [128]u8 = undefined;
        var ts = ToString{.buffer = buffer[0..]};
        try ts.string("Hello ");
        try ts.string("");
        try ts.cstring("goodbye!");
        try ts.cstring("");
        try std.testing.expectEqualSlices(u8, ts.get(), "Hello goodbye!");
    }
    {
        var buffer: [1]u8 = undefined;
        var ts = ToString{.buffer = buffer[0..]};
        try std.testing.expectError(Error.NotEnoughDestination, ts.string("Hello"));
        try std.testing.expectEqualSlices(u8, ts.get(), "");
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
        try std.testing.expectEqualSlices(u8, ts.get(), "0x00x10xf0x100xff0x100");
    }
    {
        var buffer: [1]u8 = undefined;
        var ts = ToString{.buffer = buffer[0..]};
        try std.testing.expectError(Error.NotEnoughDestination, ts.hex(0xff));
        try std.testing.expectEqualSlices(u8, ts.get(), "");
    }
    {
        var buffer: [10]u8 = undefined;
        var ts = ToString{.buffer = buffer[0..]};
        try ts.uint(0);
        try ts.uint(2);
        try ts.uint(14);
        try ts.uint(1346);
        try std.testing.expectError(Error.NotEnoughDestination, ts.uint(23912));
        try std.testing.expectEqualSlices(u8, ts.get(), "02141346");
    }
}
