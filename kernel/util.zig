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
