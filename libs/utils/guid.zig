const std = @import("std");

const utils = @import("utils.zig");

pub const Error = utils.Error;

const Guid = @This();

pub const size = 16;
pub const string_size = 36;

data: [size]u8 = undefined,

pub fn is_null(self: *const Guid) bool {
    for (self.data) |b| {
        if (b != 0) {
            return false;
        }
    }
    return true;
}

pub fn equals(a: *const Guid, b: *const Guid) bool {
    return utils.memory_compare(&a.data, &b.data);
}

pub fn from_be(self: *Guid, source: []const u8) Error!void {
    if (source.len < size) {
        return Error.NotEnoughSource;
    }
    // 00112233-4455-6677-8899-AABBCCDDEEFF
    for (source[0..size]) |*ptr, i| {
        self.data[i] = ptr.*;
    }
}

pub fn new_from_be(source: []const u8) Error!Guid {
    var guid = Guid{};
    try guid.from_be(source);
    return guid;
}

pub fn to_be(self: *const Guid, destination: []u8) Error!void {
    if (destination.len < size) {
        return Error.NotEnoughDestination;
    }
    for (destination[0..size]) |*ptr, i| {
        ptr.* = self.data[i];
    }
}

pub fn from_ms(self: *Guid, source: []const u8) Error!void {
    if (source.len < size) {
        return Error.NotEnoughSource;
    }
    // 33221100-5544-7766-8899-AABBCCDDEEFF
    self.data[0x0] = source[0x3];
    self.data[0x1] = source[0x2];
    self.data[0x2] = source[0x1];
    self.data[0x3] = source[0x0];
    self.data[0x4] = source[0x5];
    self.data[0x5] = source[0x4];
    self.data[0x6] = source[0x7];
    self.data[0x7] = source[0x6];
    self.data[0x8] = source[0x8];
    self.data[0x9] = source[0x9];
    self.data[0xa] = source[0xa];
    self.data[0xb] = source[0xb];
    self.data[0xc] = source[0xc];
    self.data[0xd] = source[0xd];
    self.data[0xe] = source[0xe];
    self.data[0xf] = source[0xf];
}

pub fn new_from_ms(source: []const u8) Error!Guid {
    var guid = Guid{};
    try guid.from_ms(source);
    return guid;
}

pub fn to_ms(self: *const Guid, destination: []u8) Error!void {
    if (destination.len < size) {
        return Error.NotEnoughDestination;
    }
    destination[0x3] = self.data[0x0];
    destination[0x2] = self.data[0x1];
    destination[0x1] = self.data[0x2];
    destination[0x0] = self.data[0x3];
    destination[0x5] = self.data[0x4];
    destination[0x4] = self.data[0x5];
    destination[0x7] = self.data[0x6];
    destination[0x6] = self.data[0x7];
    destination[0x8] = self.data[0x8];
    destination[0x9] = self.data[0x9];
    destination[0xa] = self.data[0xa];
    destination[0xb] = self.data[0xb];
    destination[0xc] = self.data[0xc];
    destination[0xd] = self.data[0xd];
    destination[0xe] = self.data[0xe];
    destination[0xf] = self.data[0xf];
}

pub fn to_string(self: *const Guid, buffer: []u8) Error!void {
    if (buffer.len < string_size) {
        return Error.NotEnoughDestination;
    }
    utils.byte_buffer(buffer[0..], self.data[0x0]);
    utils.byte_buffer(buffer[2..], self.data[0x1]);
    utils.byte_buffer(buffer[4..], self.data[0x2]);
    utils.byte_buffer(buffer[6..], self.data[0x3]);
    buffer[8] = '-';
    utils.byte_buffer(buffer[9..], self.data[0x4]);
    utils.byte_buffer(buffer[11..], self.data[0x5]);
    buffer[13] = '-';
    utils.byte_buffer(buffer[14..], self.data[0x6]);
    utils.byte_buffer(buffer[16..], self.data[0x7]);
    buffer[18] = '-';
    utils.byte_buffer(buffer[19..], self.data[0x8]);
    utils.byte_buffer(buffer[21..], self.data[0x9]);
    buffer[23] = '-';
    utils.byte_buffer(buffer[24..], self.data[0xa]);
    utils.byte_buffer(buffer[26..], self.data[0xb]);
    utils.byte_buffer(buffer[28..], self.data[0xc]);
    utils.byte_buffer(buffer[30..], self.data[0xd]);
    utils.byte_buffer(buffer[32..], self.data[0xe]);
    utils.byte_buffer(buffer[34..], self.data[0xf]);
}

const test_guid_source = "\x28\x73\x2a\xc1\x1f\xf8\xd2\x11\xba\x4b\x00\xa0\xc9\x3e\xc9\x3b";

test "MS Guid" {
    const guid = try new_from_ms(test_guid_source);

    var guid_string: [string_size]u8 = undefined;
    try guid.to_string(guid_string[0..]);
    try std.testing.expectEqualStrings("c12a7328-f81f-11d2-ba4b-00a0c93ec93b", &guid_string);

    var guid_dst: [size]u8 = undefined;
    try guid.to_ms(&guid_dst);
    try std.testing.expectEqualSlices(u8, test_guid_source, &guid_dst);
}

test "BE Guid" {
    const guid = try new_from_be(test_guid_source);

    var guid_string: [string_size]u8 = undefined;
    try guid.to_string(guid_string[0..]);
    try std.testing.expectEqualStrings("28732ac1-1ff8-d211-ba4b-00a0c93ec93b", &guid_string);

    var guid_dst: [size]u8 = undefined;
    try guid.to_be(&guid_dst);
    try std.testing.expectEqualSlices(u8, test_guid_source, &guid_dst);
}
