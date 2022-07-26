const std = @import("std");

const utils = @import("utils.zig");
const Error = utils.Error;

pub fn PackedArray(comptime T: type, count: usize) type {
    const Traits = @typeInfo(T);
    const T2 = switch (Traits) {
        std.builtin.TypeId.Int => T,
        std.builtin.TypeId.Bool => u1,
        std.builtin.TypeId.Enum => |enum_type| enum_type.tag_type,
        else => @compileError("Invalid Type"),
    };
    const is_enum = switch (Traits) {
        std.builtin.TypeId.Enum => true,
        else => false,
    };

    return struct {
        const Self = @This();

        const len = count;
        const Type = T;
        const InnerType = T2;
        const type_bit_size = utils.int_bit_size(InnerType);
        const Word = usize;
        const word_bit_size = utils.int_bit_size(Word);
        const WordShiftType = utils.IntLog2Type(Word);
        const values_per_word = word_bit_size / type_bit_size;
        const word_count =
            utils.align_up(count * type_bit_size, word_bit_size) / word_bit_size;
        const mask: Word = (1 << type_bit_size) - 1;

        contents: [word_count]Word = undefined,

        pub fn get(self: *const Self, index: usize) Error!Type {
            if (index >= len) {
                return Error.OutOfBounds;
            }
            const array_index = index / values_per_word;
            const shift = @intCast(WordShiftType,
                (index % values_per_word) * type_bit_size);
            const inner_value = @intCast(InnerType,
                (self.contents[array_index] >> shift) & mask);
            if (is_enum) {
                return @intToEnum(Type, inner_value);
            } else {
                return @bitCast(Type, inner_value);
            }
        }

        pub fn set(self: *Self, index: usize, value: Type) Error!void {
            if (index >= len) {
                return Error.OutOfBounds;
            }
            const array_index = index / values_per_word;
            const shift = @intCast(WordShiftType,
                (index % values_per_word) * type_bit_size);
            self.contents[array_index] =
                (self.contents[array_index] & ~(mask << shift)) |
                (@intCast(Word, @bitCast(InnerType, value)) << shift);
        }

        pub fn reset(self: *Self) void {
            for (self.contents[0..]) |*ptr| {
                ptr.* = 0;
            }
        }
    };
}

fn test_PackedBoolArray(comptime size: usize) !void {
    var pa: PackedArray(bool, size) = undefined;
    pa.reset();

    // Make sure get works
    try std.testing.expectEqual(false, try pa.get(0));
    try std.testing.expectEqual(false, try pa.get(1));
    try std.testing.expectEqual(false, try pa.get(size - 3));
    try std.testing.expectEqual(false, try pa.get(size - 2));
    try std.testing.expectEqual(false, try pa.get(size - 1));

    // Set and unset the first bit and check it
    try pa.set(0, true);
    try std.testing.expectEqual(true, try pa.get(0));
    try pa.set(0, false);
    try std.testing.expectEqual(false, try pa.get(0));

    // Set a spot near the end
    try pa.set(size - 2, true);
    try std.testing.expectEqual(false, try pa.get(0));
    try std.testing.expectEqual(false, try pa.get(1));
    try std.testing.expectEqual(false, try pa.get(size - 3));
    try std.testing.expectEqual(true, try pa.get(size - 2));
    try std.testing.expectEqual(false, try pa.get(size - 1));

    // Invalid Operations
    try std.testing.expectError(Error.OutOfBounds, pa.get(size));
    try std.testing.expectError(Error.OutOfBounds, pa.get(size + 100));
    try std.testing.expectError(Error.OutOfBounds, pa.set(size, true));
    try std.testing.expectError(Error.OutOfBounds, pa.set(size + 100, true));
}

test "PackedArray" {
    try test_PackedBoolArray(5);
    try test_PackedBoolArray(8);
    try test_PackedBoolArray(13);
    try test_PackedBoolArray(400);

    // Int Type
    {
        var pa: PackedArray(u7, 9) = undefined;
        pa.reset();
        try pa.set(0, 13);
        try std.testing.expectEqual(@as(u7, 13), try pa.get(0));
        try pa.set(1, 12);
        try std.testing.expectEqual(@as(u7, 12), try pa.get(1));
        try std.testing.expectEqual(@as(u7, 13), try pa.get(0));
        try pa.set(8, 47);
        try std.testing.expectEqual(@as(u7, 47), try pa.get(8));
    }

    // Enum Type
    {
        const Type = enum (u2) {
            a,
            b,
            c,
            d,
        };
        var pa: PackedArray(Type, 9) = undefined;
        pa.reset();
        try pa.set(0, .a);
        try std.testing.expectEqual(Type.a, try pa.get(0));
        try pa.set(1, .b);
        try std.testing.expectEqual(Type.b, try pa.get(1));
        try std.testing.expectEqual(Type.a, try pa.get(0));
        try pa.set(8, .d);
        try std.testing.expectEqual(Type.d, try pa.get(8));
    }
}
