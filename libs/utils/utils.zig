const std = @import("std");
const builtin = @import("builtin");

const unicode = @import("unicode.zig");
pub const Utf8ToUtf32 = unicode.Utf8ToUtf32;
pub const UnicodeError = unicode.Error;

pub const AnsiEscProcessor = @import("AnsiEscProcessor.zig");

pub const Guid = @import("guid.zig");

pub const ToString = @import("ToString.zig");

pub const Cksum = @import("Cksum.zig");

pub const Error = error {
    Unknown,
    OutOfBounds,
    NotEnoughSource,
    NotEnoughDestination,
};

// NOTE: DO NOT TRY TO REMOVE INLINE ON THESE, WILL BREAK LOW KERNEL
pub fn Ki(x: usize) callconv(.Inline) usize {
    return x << 10;
}

pub fn Mi(x: usize) callconv(.Inline) usize {
    return x << 20;
}

pub fn Gi(x: usize) callconv(.Inline) usize {
    return x << 30;
}

pub fn Ti(x: usize) callconv(.Inline) usize {
    return x << 40;
}

pub fn align_down(value: usize, align_by: usize) usize {
    return value & (~align_by +% 1);
}

pub fn align_up(value: usize, align_by: usize) usize {
    return align_down(value +% align_by -% 1, align_by);
}

pub fn padding(value: usize, align_by: usize) callconv(.Inline) usize {
    return -%value & (align_by - 1);
}

pub fn div_round_up(comptime Type: type, n: Type, d: Type) callconv(.Inline) Type {
    return n / d + (if (n % d != 0) @as(Type, 1) else @as(Type, 0));
}

test "div_round_up" {
    try std.testing.expectEqual(@as(u8, 0), div_round_up(u8, 0, 2));
    try std.testing.expectEqual(@as(u8, 1), div_round_up(u8, 1, 2));
    try std.testing.expectEqual(@as(u8, 1), div_round_up(u8, 2, 2));
    try std.testing.expectEqual(@as(u8, 2), div_round_up(u8, 3, 2));
    try std.testing.expectEqual(@as(u8, 2), div_round_up(u8, 4, 2));
}

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

pub fn zero_init(comptime Type: type) Type {
    const Traits = @typeInfo(Type);
    comptime var CastThrough = Type;
    switch (Traits) {
        std.builtin.TypeId.Int => {
            CastThrough = Type;
        },
        std.builtin.TypeId.Bool => {
            return false;
        },
        std.builtin.TypeId.Struct => |struct_type| {
            if (struct_type.layout != std.builtin.TypeInfo.ContainerLayout.Packed) {
                @compileError("Struct must be packed!");
            }
            var struct_var: Type = undefined;
            inline for (struct_type.fields) |field| {
                @field(struct_var, field.name) = zero_init(field.field_type);
            }
            return struct_var;
        },
        else => CastThrough = std.meta.IntType(.unsigned, @sizeOf(Type) * 8),
    }
    return @bitCast(Type, @intCast(CastThrough, 0));
}

pub fn packed_bit_size(comptime Type: type) comptime_int {
    const Traits = @typeInfo(Type);
    switch (Traits) {
        std.builtin.TypeId.Int => |int_type| {
            return int_type.bits;
        },
        std.builtin.TypeId.Bool => {
            return 1;
        },
        std.builtin.TypeId.Array => |array_type| {
            return packed_bit_size(array_type.child) * array_type.len;
        },
        std.builtin.TypeId.Struct => |struct_type| {
            if (struct_type.layout != std.builtin.TypeInfo.ContainerLayout.Packed) {
                @compileError("Struct must be packed!");
            }
            comptime var total_size: comptime_int = 0;
            inline for (struct_type.fields) |field| {
                total_size += packed_bit_size(field.field_type);
            }
            return total_size;
        },
        else => {
            @compileLog("Unsupported Type is ", @typeName(Type));
            @compileError("Unsupported Type");
        }
    }
}

/// @intToEnum can't be used to test if a value is a valid Enum, so this wraps
/// it and gives that functionality.
pub fn int_to_enum(comptime EnumType: type, value: std.meta.Tag(EnumType)) ?EnumType {
    const type_info = @typeInfo(EnumType).Enum;
    inline for (type_info.fields) |*field| {
        if (@intCast(type_info.tag_type, field.value) == value) {
            return @intToEnum(EnumType, value);
        }
    }
    return null;
}

pub fn valid_enum(comptime EnumType: type, value: EnumType) bool {
    return int_to_enum(EnumType, @bitCast(std.meta.Tag(EnumType), value)) != null;
}

test "int_to_enum" {
    const assert = std.debug.assert;

    const Abc = enum(u8) {
        A = 0,
        B = 1,
        C = 12,
    };

    // Check with Literals
    assert(int_to_enum(Abc, @intCast(std.meta.Tag(Abc), 0)).? == Abc.A);
    assert(int_to_enum(Abc, @intCast(std.meta.Tag(Abc), 1)).? == Abc.B);
    assert(int_to_enum(Abc, @intCast(std.meta.Tag(Abc), 2)) == null);
    assert(int_to_enum(Abc, @intCast(std.meta.Tag(Abc), 11)) == null);
    assert(int_to_enum(Abc, @intCast(std.meta.Tag(Abc), 12)).? == Abc.C);
    assert(int_to_enum(Abc, @intCast(std.meta.Tag(Abc), 13)) == null);
    assert(int_to_enum(Abc, @intCast(std.meta.Tag(Abc), 0xFF)) == null);

    // Check with Variable
    var x: std.meta.Tag(Abc) = 0;
    assert(int_to_enum(Abc, x).? == Abc.A);
    x = 0xFF;
    assert(int_to_enum(Abc, x) == null);

    // valid_enum
    assert(valid_enum(Abc, @intToEnum(Abc, @as(u8, 0))));
    // TODO: This is a workaround bitcast of a const Enum causing a compiler assert
    // Looks like it's related to https://github.com/ziglang/zig/issues/1036
    var invalid_enum_value: u8 = 4;
    assert(!valid_enum(Abc, @ptrCast(*const Abc, &invalid_enum_value).*));
    // assert(valid_enum(Abc, @bitCast(Abc, @as(u8, 4))));
}

pub fn enum_name(comptime EnumType: type, value: EnumType) ?[]const u8 {
    const type_info = @typeInfo(EnumType).Enum;
    inline for (type_info.fields) |*field| {
        var enum_value = @ptrCast(*const type_info.tag_type, &value).*;
        if (@intCast(type_info.tag_type, field.value) == enum_value) {
            return field.name;
        }
    }
    return null;
}

pub fn max(comptime T: type, a: T, b: T) T {
    return if (a > b) a else b;
}

pub fn min(comptime T: type, a: T, b: T) T {
    return if (a < b) a else b;
}

/// Returns true if the contents of the slices `a` and `b` are the same.
pub fn memory_compare(a: []const u8, b: []const u8) callconv(.Inline) bool {
    if (a.len != b.len) return false;
    for (a[0..]) |value, i| {
        if (value != b[i]) return false;
    }
    return true;
}

/// Copy contents from `source` to `destination`.
///
/// If `source.len != destination.len` then the copy is truncated.
pub fn memory_copy_truncate(destination: []u8, source: []const u8) callconv(.Inline) usize {
    const size = min(usize, destination.len, source.len);
    for (destination[0..size]) |*ptr, i| {
        ptr.* = source[i];
    }
    return size;
}

pub fn memory_copy_error(destination: []u8, source: []const u8) callconv(.Inline) Error!usize {
    if (destination.len < source.len) {
        return Error.NotEnoughDestination;
    }
    const size = source.len;
    for (destination[0..size]) |*ptr, i| {
        ptr.* = source[i];
    }
    return size;
}

pub fn memory_copy_anyptr(destination: []u8, source: anytype) callconv(.Inline) void {
    const s = @ptrCast([*]const u8, source);
    for (destination[0..]) |*ptr, i| {
        ptr.* = s[i];
    }
}

/// Set all the elements of `destination` to `value`.
pub fn memory_set(destination: []u8, value: u8) callconv(.Inline) void {
    for (destination[0..]) |*ptr| {
        ptr.* = value;
    }
}

pub fn max_of_int(comptime T: type) T {
    const Traits = @typeInfo(T);
    return if (Traits.Int.signedness == .signed)
        (1 << (Traits.Int.bits - 1)) - 1
    else
        @as(T, 0) -% 1;
}

test "max_of_int" {
    try std.testing.expect(max_of_int(u16) == 0xffff);
    try std.testing.expect(max_of_int(i16) == 0x7fff);
}

pub fn add_signed_to_unsigned(
        comptime uT: type, a: uT, comptime iT: type, b: iT) ?uT {
    var result: uT = undefined;
    if (@addWithOverflow(uT, a, @bitCast(uT, b), &result)) {
        if (b > 0 and result < a) {
            return null;
        }
    } else if (b < 0 and result > a) {
        return null;
    }
    return result;
}

pub fn add_isize_to_usize(a: usize, b: isize) callconv(.Inline) ?usize {
    return add_signed_to_unsigned(usize, a, isize, b);
}

test "add_signed_to_unsigned" {
    try std.testing.expect(add_isize_to_usize(0, 0).? == 0);
    try std.testing.expect(add_isize_to_usize(0, 10).? == 10);
    try std.testing.expect(add_isize_to_usize(0, -10) == null);
    const max_usize = max_of_int(usize);
    try std.testing.expect(add_isize_to_usize(max_usize, 0).? == max_usize);
    try std.testing.expect(add_isize_to_usize(max_usize, -10).? == max_usize - 10);
    try std.testing.expect(add_isize_to_usize(max_usize, 10) == null);
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

pub fn int_log2(comptime Type: type, value: Type) Type {
    return @sizeOf(Type) * 8 - 1 - @clz(Type, value);
}

fn test_int_log2(value: usize, expected: usize) !void {
    try std.testing.expectEqual(expected, int_log2(usize, value));
}

test "int_log2" {
    try test_int_log2(1, 0);
    try test_int_log2(2, 1);
    try test_int_log2(4, 2);
    try test_int_log2(8, 3);
    try test_int_log2(16, 4);
    try test_int_log2(32, 5);
    try test_int_log2(64, 6);
    try test_int_log2(128, 7);
}

pub fn hex_char_len(comptime Type: type, value: Type) Type {
    if (value == 0) {
        return 1;
    }
    return int_log2(Type, value) / 4 + 1;
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

pub fn int_bit_size(comptime Type: type) usize {
    return @typeInfo(Type).Int.bits;
}

pub fn IntLog2Type(comptime Type: type) type {
    return @Type(std.builtin.TypeInfo{.Int = std.builtin.TypeInfo.Int{
        .signedness = .unsigned,
        .bits = int_log2(usize, int_bit_size(Type)),
    }});
}

fn test_IntLog2Type(comptime Type: type, expected: usize) !void {
    try std.testing.expectEqual(expected, int_bit_size(IntLog2Type(Type)));
}

test "Log2Int" {
    try test_IntLog2Type(u2, 1);
    try test_IntLog2Type(u32, 5);
    try test_IntLog2Type(u64, 6);
}

pub const UsizeLog2Type = IntLog2Type(usize);

pub fn select_nibble(comptime Type: type, value: Type, which: usize) u4 {
    return @intCast(u4,
        (value >> (@intCast(IntLog2Type(Type), which) * 4)) & 0xf);
}

fn test_select_nibble(comptime Type: type,
        value: Type, which: usize, expected: u4) !void {
    try std.testing.expectEqual(expected, select_nibble(Type, value, which));
}

test "select_nibble" {
    try test_select_nibble(u8, 0xaf, 0, 0xf);
    try test_select_nibble(u8, 0xaf, 1, 0xa);
    try test_select_nibble(u16, 0x1234, 0, 0x4);
    try test_select_nibble(u16, 0x1234, 1, 0x3);
    try test_select_nibble(u16, 0x1234, 2, 0x2);
    try test_select_nibble(u16, 0x1234, 3, 0x1);
}

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
        const type_bit_size = int_bit_size(InnerType);
        const Word = usize;
        const word_bit_size = int_bit_size(Word);
        const WordShiftType = IntLog2Type(Word);
        const values_per_word = word_bit_size / type_bit_size;
        const word_count =
            align_up(count * type_bit_size, word_bit_size) / word_bit_size;
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

pub fn pow2_round_up(comptime Type: type, value: Type) Type {
    if (value < 3) {
        return value;
    } else {
        return @intCast(Type, 1) <<
            @intCast(IntLog2Type(Type), (int_log2(Type, value - 1) + 1));
    }
}

test "pow2_round_up" {
    try std.testing.expectEqual(@as(u8, 0), pow2_round_up(u8, 0));
    try std.testing.expectEqual(@as(u8, 1), pow2_round_up(u8, 1));
    try std.testing.expectEqual(@as(u8, 2), pow2_round_up(u8, 2));
    try std.testing.expectEqual(@as(u8, 4), pow2_round_up(u8, 3));
    try std.testing.expectEqual(@as(u8, 4), pow2_round_up(u8, 4));
    try std.testing.expectEqual(@as(u8, 8), pow2_round_up(u8, 5));
    try std.testing.expectEqual(@as(u8, 8), pow2_round_up(u8, 6));
    try std.testing.expectEqual(@as(u8, 8), pow2_round_up(u8, 7));
    try std.testing.expectEqual(@as(u8, 8), pow2_round_up(u8, 8));
    try std.testing.expectEqual(@as(u8, 16), pow2_round_up(u8, 9));
    try std.testing.expectEqual(@as(u8, 16), pow2_round_up(u8, 16));
    try std.testing.expectEqual(@as(u8, 32), pow2_round_up(u8, 17));
}

pub fn make_slice(comptime Type: type, ptr: [*]Type, len: usize) callconv(.Inline) []Type {
    var slice: []Type = undefined;
    slice.ptr = ptr;
    slice.len = len;
    return slice;
}

pub fn to_bytes(value: anytype) callconv(.Inline) []u8 {
    const Type = @TypeOf(value);
    const Traits = @typeInfo(Type);
    switch (Traits) {
        std.builtin.TypeId.Pointer => |pointer_type| {
            const count = switch (pointer_type.size) {
                .One => 1,
                .Slice => value.len,
                else => {
                    @compileLog("Unsupported Type is ", @typeName(Type));
                    @compileError("Unsupported Type");
                }
            };
            return make_slice(u8, @ptrCast([*]u8, value),
                @sizeOf(pointer_type.child) * count);
        },
        else => {
            @compileLog("Unsupported Type is ", @typeName(Type));
            @compileError("Unsupported Type");
        }
    }
}

pub fn make_const_slice(
        comptime Type: type, ptr: [*]const Type, len: usize) callconv(.Inline) []const Type {
    var slice: []const Type = undefined;
    slice.ptr = ptr;
    slice.len = len;
    return slice;
}

pub fn to_const_bytes(value: anytype) callconv(.Inline) []const u8 {
    const Type = @TypeOf(value);
    const Traits = @typeInfo(Type);
    switch (Traits) {
        std.builtin.TypeId.Pointer => |pointer_type| {
            const count = switch (pointer_type.size) {
                .One => 1,
                .Slice => value.len,
                else => {
                    @compileLog("Unsupported Type is ", @typeName(Type));
                    @compileError("Unsupported Type");
                }
            };
            return make_const_slice(u8, @ptrCast([*]const u8, value),
                @sizeOf(pointer_type.child) * count);
        },
        else => {
            @compileLog("Unsupported Type is ", @typeName(Type));
            @compileError("Unsupported Type");
        }
    }
}

/// What to discard if there is no more room.
const CircularBufferDiscard = enum {
    DiscardNewest,
    DiscardOldest,
};

pub fn CircularBuffer(
        comptime Type: type, len_arg: usize, discard: CircularBufferDiscard) type {
    return struct {
        const Self = @This();
        const max_len = len_arg;

        contents: [max_len]Type = undefined,
        start: usize = 0,
        len: usize = 0,

        pub fn reset(self: *Self) void {
            self.start = 0;
            self.len = 0;
        }

        fn wrapped_offset(pos: usize, offset: usize) callconv(.Inline) usize {
            return (pos + offset) % max_len;
        }

        fn increment(pos: *usize) callconv(.Inline) void {
            pos.* = wrapped_offset(pos.*, 1);
        }

        pub fn push(self: *Self, value: Type) void {
            if (self.len == max_len) {
                if (discard == .DiscardNewest) {
                    return;
                } else { // DiscardOldest
                    increment(&self.start);
                }
            } else {
                self.len += 1;
            }
            self.contents[wrapped_offset(self.start, self.len - 1)] = value;
        }

        pub fn pop(self: *Self) ?Type {
            if (self.len == 0) return null;
            self.len -= 1;
            defer increment(&self.start);
            return self.contents[self.start];
        }

        pub fn get(self: *const Self, offset: usize) ?Type {
            if (offset >= self.len) return null;
            return self.contents[wrapped_offset(self.start, offset)];
        }

        pub fn peek_start(self: *const Self) ?Type {
            return self.get(0);
        }

        pub fn peek_end(self: *const Self) ?Type {
            if (self.len == 0) return null;
            return self.get(self.len - 1);
        }
    };
}

fn test_circular_buffer(comptime discard: CircularBufferDiscard) !void {
    var buffer = CircularBuffer(usize, 4, discard){};
    const nil: ?usize = null;

    // Empty
    try std.testing.expectEqual(@as(usize, 0), buffer.len);
    try std.testing.expectEqual(nil, buffer.pop());
    try std.testing.expectEqual(nil, buffer.peek_start());
    try std.testing.expectEqual(nil, buffer.get(0));
    try std.testing.expectEqual(nil, buffer.peek_end());

    // Push Some Values
    buffer.push(1);
    try std.testing.expectEqual(@as(usize, 1), buffer.len);
    try std.testing.expectEqual(@as(usize, 1), buffer.peek_start().?);
    try std.testing.expectEqual(@as(usize, 1), buffer.peek_end().?);
    buffer.push(2);
    try std.testing.expectEqual(@as(usize, 2), buffer.peek_end().?);
    buffer.push(3);
    try std.testing.expectEqual(@as(usize, 3), buffer.peek_end().?);
    try std.testing.expectEqual(@as(usize, 3), buffer.len);

    // Test get
    try std.testing.expectEqual(@as(usize, 1), buffer.get(0).?);
    try std.testing.expectEqual(@as(usize, 2), buffer.get(1).?);
    try std.testing.expectEqual(@as(usize, 3), buffer.get(2).?);
    try std.testing.expectEqual(nil, buffer.get(3));

    // Pop The Values
    try std.testing.expectEqual(@as(usize, 1), buffer.peek_start().?);
    try std.testing.expectEqual(@as(usize, 1), buffer.pop().?);
    try std.testing.expectEqual(@as(usize, 2), buffer.peek_start().?);
    try std.testing.expectEqual(@as(usize, 2), buffer.pop().?);
    try std.testing.expectEqual(@as(usize, 3), buffer.peek_start().?);
    try std.testing.expectEqual(@as(usize, 3), buffer.pop().?);

    // It's empty again
    try std.testing.expectEqual(@as(usize, 0), buffer.len);
    try std.testing.expectEqual(nil, buffer.pop());
    try std.testing.expectEqual(nil, buffer.peek_start());
    try std.testing.expectEqual(nil, buffer.get(0));
    try std.testing.expectEqual(nil, buffer.peek_end());

    // Fill it past capacity
    buffer.push(5);
    try std.testing.expectEqual(@as(usize, 5), buffer.peek_end().?);
    buffer.push(4);
    try std.testing.expectEqual(@as(usize, 4), buffer.peek_end().?);
    buffer.push(3);
    try std.testing.expectEqual(@as(usize, 3), buffer.peek_end().?);
    buffer.push(2);
    try std.testing.expectEqual(@as(usize, 2), buffer.peek_end().?);
    buffer.push(1);
    if (discard == .DiscardOldest) {
        try std.testing.expectEqual(@as(usize, 1), buffer.peek_end().?);
    }
    try std.testing.expectEqual(@as(usize, 4), buffer.len);

    // Test get
    var index: usize = 0;
    if (discard == .DiscardNewest) {
        try std.testing.expectEqual(@as(usize, 5), buffer.get(index).?);
        index += 1;
    }
    try std.testing.expectEqual(@as(usize, 4), buffer.get(index).?);
    index += 1;
    try std.testing.expectEqual(@as(usize, 3), buffer.get(index).?);
    index += 1;
    try std.testing.expectEqual(@as(usize, 2), buffer.get(index).?);
    index += 1;
    if (discard == .DiscardOldest) {
        try std.testing.expectEqual(@as(usize, 1), buffer.get(index).?);
        index += 1;
    }
    try std.testing.expectEqual(nil, buffer.get(index));

    // Pop The Values
    if (discard == .DiscardNewest) {
        try std.testing.expectEqual(@as(usize, 5), buffer.peek_start().?);
        try std.testing.expectEqual(@as(usize, 5), buffer.pop().?);
    }
    try std.testing.expectEqual(@as(usize, 4), buffer.peek_start().?);
    try std.testing.expectEqual(@as(usize, 4), buffer.pop().?);
    try std.testing.expectEqual(@as(usize, 3), buffer.pop().?);
    try std.testing.expectEqual(@as(usize, 2), buffer.peek_start().?);
    try std.testing.expectEqual(@as(usize, 2), buffer.pop().?);
    if (discard == .DiscardOldest) {
        try std.testing.expectEqual(@as(usize, 1), buffer.peek_start().?);
        try std.testing.expectEqual(@as(usize, 1), buffer.pop().?);
    }

    // It's empty yet again
    try std.testing.expectEqual(@as(usize, 0), buffer.len);
    try std.testing.expectEqual(nil, buffer.pop());
    try std.testing.expectEqual(nil, buffer.peek_start());
    try std.testing.expectEqual(nil, buffer.get(0));
    try std.testing.expectEqual(nil, buffer.peek_end());
}

test "CircularBuffer(.DiscardNewest)" {
    try test_circular_buffer(.DiscardNewest);
}

test "CircularBuffer(.DiscardOldest)" {
    try test_circular_buffer(.DiscardOldest);
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

/// Simple Pseudo-random number generator
/// See https://en.wikipedia.org/wiki/Linear_congruential_generator
pub fn Rand(comptime Type: type) type {
    return struct {
        const Self = @This();

        const a: u64 = 6364136223846793005;
        const c: u64 = 1442695040888963407;

        seed: u64,

        pub fn get(self: *Self) Type {
            self.seed = a *% self.seed +% c;
            return @truncate(Type, self.seed);
        }
    };
}

test "Rand" {
    var r = Rand(u64){.seed = 0};
    try std.testing.expectEqual(@as(u64, 1442695040888963407), r.get());
    try std.testing.expectEqual(@as(u64, 1876011003808476466), r.get());
    try std.testing.expectEqual(@as(u64, 11166244414315200793), r.get());
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

pub const Point = struct {
    x: u32 = 0,
    y: u32 = 0,
};
