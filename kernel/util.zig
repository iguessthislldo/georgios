const builtin = @import("builtin");

pub inline fn KiB(x: usize) usize {
    return x * (1 << 10);
}

pub inline fn MiB(x: usize) usize {
    return x * (1 << 20);
}

pub inline fn GiB(x: usize) usize {
    return x * (1 << 30);
}

pub inline fn TiB(x: usize) usize {
    return x * (1 << 40);
}

pub inline fn align_down(value: usize, align_by: usize) usize {
    return value & -%(align_by);
}

pub inline fn align_up(value: usize, align_by: usize) usize {
    return align_down(value + align_by - 1, align_by);
}

pub inline fn padding(value: usize, align_by: usize) usize {
    return -%value & (align_by - 1);
}

pub fn isspace(c: u8) bool {
    return c == ' ' or c == '\n' or c == '\t' or c == '\r';
}

pub fn zero_init(comptime Type: type) Type {
    comptime const Traits = @typeInfo(Type);
    comptime var CastThrough = Type;
    switch (Traits) {
        builtin.TypeId.Int => |int_type| {
            CastThrough = Type;
        },
        builtin.TypeId.Bool => {
            return false;
        },
        builtin.TypeId.Struct => |struct_type| {
            if (struct_type.layout != builtin.TypeInfo.ContainerLayout.Packed) {
                @compileError("Struct must be packed!");
            }
            var struct_var: Type = undefined;
            inline for (struct_type.fields) |field| {
                @field(struct_var, field.name) = zero_init(field.field_type);
            }
            return struct_var;
        },
        else => CastThrough = @IntType(false, @sizeOf(Type) * 8),
    }
    return @bitCast(Type, @intCast(CastThrough, 0));
}

/// @intToEnum can't be used to test if a value is a valid Enum, so this wraps
/// it and gives that functionality.
pub fn int_to_enum(comptime EnumType: type, value: @TagType(EnumType)) ?EnumType {
    const type_info = @typeInfo(EnumType).Enum;
    inline for (type_info.fields) |*field| {
        if (@intCast(type_info.tag_type, field.value) == value) {
            return @intToEnum(EnumType, value);
        }
    }
    return null;
}

test "int_to_enum" {
    const std = @import("std");
    const assert = std.debug.assert;

    const Abc = enum(u8) {
        A = 0,
        B = 1,
        C = 12,
    };

    // Check with Literals
    assert(int_to_enum(Abc, @intCast(@TagType(Abc), 0)).? == Abc.A);
    assert(int_to_enum(Abc, @intCast(@TagType(Abc), 1)).? == Abc.B);
    assert(int_to_enum(Abc, @intCast(@TagType(Abc), 2)) == null);
    assert(int_to_enum(Abc, @intCast(@TagType(Abc), 11)) == null);
    assert(int_to_enum(Abc, @intCast(@TagType(Abc), 12)).? == Abc.C);
    assert(int_to_enum(Abc, @intCast(@TagType(Abc), 13)) == null);
    assert(int_to_enum(Abc, @intCast(@TagType(Abc), 0xFF)) == null);

    // Check with Variable
    var x: @TagType(Abc) = 0;
    assert(int_to_enum(Abc, x).? == Abc.A);
    x = 0xFF;
    assert(int_to_enum(Abc, x) == null);
}

pub fn max(comptime T: type, a: T, b: T) T {
    return if (a > b) a else b;
}

pub fn min(comptime T: type, a: T, b: T) T {
    return if (a < b) a else b;
}

/// Returns true if the contents of the slices `a` and `b` are the same.
pub inline fn memory_compare(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    for (a[0..]) |value, i| {
        if (value != b[i]) return false;
    }
    return true;
}

/// Copy contents from `source` to `destination`.
///
/// If `source.len != destination.len` then the copy is truncated.
pub inline fn memory_copy(destination: []u8, source: []const u8) void {
    const size = min(usize, destination.len, source.len);
    for (destination[0..size]) |*ptr, i| {
        ptr.* = source[i];
    }
}

/// Set all the elements of `destination` to `value`.
pub inline fn memory_set(destination: []u8, value: u8) void {
    for (destination[0..]) |*ptr| {
        ptr.* = value;
    }
}

pub fn max_of_int(comptime T: type) T {
    comptime const Traits = @typeInfo(T);
    return if (Traits.Int.is_signed)
        (1 << (Traits.Int.bits - 1)) - 1
    else
        T(0) -% 1;
}

test "max_of_int" {
    const std = @import("std");
    std.testing.expect(max_of_int(u16) == 0xffff);
    std.testing.expect(max_of_int(i16) == 0x7fff);
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

pub inline fn add_isize_to_usize(a: usize, b: isize) ?usize {
    return add_signed_to_unsigned(usize, a, isize, b);
}

test "add_signed_to_unsigned" {
    const std = @import("std");
    std.testing.expect(add_isize_to_usize(0, 0).? == 0);
    std.testing.expect(add_isize_to_usize(0, 10).? == 10);
    std.testing.expect(add_isize_to_usize(0, -10) == null);
    const max_usize = max_of_int(usize);
    std.testing.expect(add_isize_to_usize(max_usize, 0).? == max_usize);
    std.testing.expect(add_isize_to_usize(max_usize, -10).? == max_usize - 10);
    std.testing.expect(add_isize_to_usize(max_usize, 10) == null);
}

pub inline fn string_length(bytes: []const u8) usize {
    for (bytes[0..]) |*ptr, i| {
        if (ptr.* == 0) {
            return i;
        }
    }
    return bytes.len;
}

pub fn int_log2(comptime Type: type, value: Type) Type {
    return @sizeOf(Type) * 8 - 1 - @clz(Type, value);
}

fn test_int_log2(value: usize, expected: usize) void {
    const std = @import("std");
    std.testing.expectEqual(expected, int_log2(usize, value));
}

test "int_log2" {
    test_int_log2(1, 0);
    test_int_log2(2, 1);
    test_int_log2(4, 2);
    test_int_log2(8, 3);
    test_int_log2(16, 4);
    test_int_log2(32, 5);
    test_int_log2(64, 6);
    test_int_log2(128, 7);
}

pub fn int_bit_size(comptime IntType: type) usize {
    return @typeInfo(IntType).Int.bits;
}

pub fn IntLog2Type(comptime IntType: type) type {
    return @Type(builtin.TypeInfo{.Int = builtin.TypeInfo.Int{
        .is_signed = false,
        .bits = int_log2(usize, int_bit_size(IntType)),
    }});
}

fn test_IntLog2Type(comptime IntType: type, expected: usize) void {
    const std = @import("std");
    std.testing.expectEqual(expected, int_bit_size(IntLog2Type(IntType)));
}

test "Log2IntType" {
    test_IntLog2Type(u2, 1);
    test_IntLog2Type(u32, 5);
    test_IntLog2Type(u64, 6);
}

pub fn select_nibble(comptime IntType: type, value: IntType, which: usize) u4 {
    return @intCast(u4,
        (value >> (@intCast(IntLog2Type(IntType), which) * 4)) & 0xf);
}

fn test_select_nibble(comptime IntType: type,
        value: IntType, which: usize, expected: u4) void {
    const std = @import("std");
    std.testing.expectEqual(expected, select_nibble(IntType, value, which));
}

test "select_nibble" {
    test_select_nibble(u8, 0xaf, 0, 0xf);
    test_select_nibble(u8, 0xaf, 1, 0xa);
    test_select_nibble(u16, 0x1234, 0, 0x4);
    test_select_nibble(u16, 0x1234, 1, 0x3);
    test_select_nibble(u16, 0x1234, 2, 0x2);
    test_select_nibble(u16, 0x1234, 3, 0x1);
}
