const std = @import("std");
const builtin = @import("builtin");

const unicode = @import("unicode.zig");
pub const Utf8ToUtf32 = unicode.Utf8ToUtf32;
pub const UnicodeError = unicode.Error;
pub const AnsiEscProcessor = @import("AnsiEscProcessor.zig");
pub const Guid = @import("Guid.zig");
pub const ToString = @import("ToString.zig");
pub const Cksum = @import("Cksum.zig");
pub const WordIterator = @import("WordIterator.zig");
pub const Bdf = @import("Bdf.zig");
pub const List = @import("list.zig").List;
pub const CircularBuffer = @import("circular_buffer.zig").CircularBuffer;
pub const PackedArray = @import("packed_array.zig").PackedArray;

const mem = @import("mem.zig");
pub const memory_compare = mem.memory_compare;
pub const memory_copy_truncate = mem.memory_copy_truncate;
pub const memory_copy_error = mem.memory_copy_error;
pub const memory_copy_anyptr = mem.memory_copy_anyptr;
pub const memory_set = mem.memory_set;
pub const to_bytes = mem.to_bytes;
pub const to_const_bytes = mem.to_const_bytes;
pub const empty_slice = mem.empty_slice;
pub const TestAlloc = mem.TestAlloc;

const str = @import("str.zig");
pub const isspace = str.isspace;
pub const stripped_string_size = str.stripped_string_size;
pub const string_length = str.string_length;
pub const cstring_length = str.cstring_length;
pub const cstring_to_slice = str.cstring_to_slice;
pub const cstring_to_string = str.cstring_to_string;
pub const hex_char_len = str.hex_char_len;
pub const nibble_char = str.nibble_char;
pub const byte_buffer = str.byte_buffer;
pub const starts_with = str.starts_with;
pub const ends_with = str.ends_with;
pub const StringWriter = str.StringWriter;
pub const StringReader = str.StringReader;
pub const fmt_dump_hex = str.fmt_dump_hex;

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
    const max_usize = std.math.maxInt(usize);
    try std.testing.expect(add_isize_to_usize(max_usize, 0).? == max_usize);
    try std.testing.expect(add_isize_to_usize(max_usize, -10).? == max_usize - 10);
    try std.testing.expect(add_isize_to_usize(max_usize, 10) == null);
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

pub fn pow2_round_up(comptime Type: type, value: Type) Type {
    if (value < 3) {
        return value;
    } else {
        return @intCast(Type, 1) <<
            @intCast(IntLog2Type(Type), int_log2(Type, value - 1) + 1);
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

pub fn pow2_round_down(comptime Type: type, value: Type) Type {
    if (value < 3 or (value & (value - 1)) == 0) return value;
    return @intCast(Type, 1) <<
        @intCast(IntLog2Type(Type), int_log2(Type, value - 1));
}

test "pow2_round_down" {
    try std.testing.expectEqual(@as(u8, 0), pow2_round_down(u8, 0));
    try std.testing.expectEqual(@as(u8, 1), pow2_round_down(u8, 1));
    try std.testing.expectEqual(@as(u8, 2), pow2_round_down(u8, 2));
    try std.testing.expectEqual(@as(u8, 2), pow2_round_down(u8, 3));
    try std.testing.expectEqual(@as(u8, 4), pow2_round_down(u8, 4));
    try std.testing.expectEqual(@as(u8, 4), pow2_round_down(u8, 5));
    try std.testing.expectEqual(@as(u8, 4), pow2_round_down(u8, 6));
    try std.testing.expectEqual(@as(u8, 4), pow2_round_down(u8, 7));
    try std.testing.expectEqual(@as(u8, 8), pow2_round_down(u8, 8));
    try std.testing.expectEqual(@as(u8, 8), pow2_round_down(u8, 9));
    try std.testing.expectEqual(@as(u8, 16), pow2_round_down(u8, 16));
    try std.testing.expectEqual(@as(u8, 16), pow2_round_down(u8, 17));
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

pub fn Point(comptime TheNum: type) type {
    return struct {
        const Self = @This();

        pub const Num = TheNum;

        x: Num = 0,
        y: Num = 0,

        pub fn as(self: *const Self, comptime NumType: type) Point(NumType) {
            return .{.x = @as(NumType, self.x), .y = @as(NumType, self.y)};
        }

        pub fn plus_int(self: *const Self, comptime value: anytype) Self {
            return .{.x = self.x + value, .y = self.y + value};
        }

        pub fn minus_int(self: *const Self, comptime value: anytype) Self {
            return .{.x = self.x - value, .y = self.y - value};
        }

        pub fn plus_point(self: *const Self, other: Self) Self {
            return .{.x = self.x + other.x, .y = self.y + other.y};
        }

        pub fn minus_point(self: *const Self, other: Self) Self {
            return .{.x = self.x - other.x, .y = self.y - other.y};
        }
    };
}

pub const U32Point = Point(u32);

pub fn Box(comptime PosNum: type, comptime SizeNum: type) type {
    return struct {
        pub const Pos = Point(PosNum);
        pub const Size = Point(SizeNum);

        pos: Pos = .{},
        size: Size = .{},
    };
}

pub fn any_equal(a: anytype, b: @TypeOf(a)) bool {
    const Type = @TypeOf(a);
    const ti = @typeInfo(Type);
    return switch (ti) {
        .Union => |union_ti| {
            const Tag = union_ti.tag_type.?;
            const tag_ti = @typeInfo(Tag).Enum;
            const kind = @as(Tag, a);
            if (kind != @as(Tag, b)) {
                return false;
            }
            inline for (tag_ti.fields) |field| {
                if (kind == @intToEnum(Tag, field.value)) {
                    return any_equal(@field(a, field.name), @field(b, field.name));
                }
            }
            return false;
        },
        .Pointer => |ptr_ti| {
            if (ptr_ti.size == .Slice and ptr_ti.child == u8) {
                return memory_compare(a, b);
            } else {
                return a == b;
            }
        },
        .Struct => |struct_ti| {
            inline for (struct_ti.fields) |field| {
                if (!any_equal(@field(a, field.name), @field(b, field.name))) {
                    return false;
                }
            }
            return true;
        },
        else => {
            return a == b;
        },
    };
}

const AnyEqualTestValue = union(enum) {
    Int: u32,
    String1: []const u8,
    String2: []const u8,
    Pair: struct {
        x: u16,
        y: u16,
    },
    Nil: void,

    fn eq(self: AnyEqualTestValue, other: AnyEqualTestValue) bool {
        return any_equal(self, other);
    }
};

test "any_equal" {
    const Value = AnyEqualTestValue;
    const int1 = Value{.Int = 1};
    const int2 = Value{.Int = 2};
    const str1 = Value{.String1 = "hello"};
    const str2 = Value{.String2 = "hello"};
    const pair = Value{.Pair = .{.x = 4, .y = 8}};
    const nil = Value{.Nil = .{}};
    try std.testing.expect(int1.eq(int1));
    try std.testing.expect(!int1.eq(int2));
    try std.testing.expect(!int1.eq(str1));
    try std.testing.expect(str1.eq(str1));
    try std.testing.expect(!str1.eq(str2));
    try std.testing.expect(nil.eq(nil));
    try std.testing.expect(!nil.eq(int1));
    try std.testing.expect(!pair.eq(int1));
    try std.testing.expect(!pair.eq(.{.Pair = .{.x = 4, .y = 9}}));
    try std.testing.expect(pair.eq(.{.Pair = .{.x = 4, .y = 8}}));
}

pub const GenericWriter = struct {
    pub const GenericWriterError = error {
        GenericWriterError,
    };

    impl: *anyopaque,
    write_fn_impl: fn(impl: *anyopaque, bytes: []const u8) GenericWriterError!usize,

    fn write_fn(self: *GenericWriter, bytes: []const u8) GenericWriterError!usize {
        return self.write_fn_impl(self.impl, bytes);
    }

    pub const Writer = std.io.Writer(*GenericWriter, GenericWriterError, write_fn);

    pub fn writer(self: *GenericWriter) Writer {
        return .{.context = self};
    }
};

pub fn GenericWriterImpl(comptime RealWriter: type) type {
    return struct {
        const Self = @This();

        const GenericWriterError = GenericWriter.GenericWriterError;

        real_writer: *RealWriter = undefined,
        generic_writer: GenericWriter = undefined,

        fn write_fn_impl(impl: *anyopaque, bytes: []const u8) GenericWriterError!usize {
            const self = @ptrCast(*Self, @alignCast(@alignOf(Self), impl));
            return self.real_writer.write(bytes) catch GenericWriterError.GenericWriterError;
        }

        pub fn init(self: *Self, real_writer: *RealWriter) void {
            self.* = .{
                .real_writer = real_writer,
                .generic_writer = .{
                    .impl = @ptrCast(*anyopaque, self),
                    .write_fn_impl = write_fn_impl,
                },
            };
        }

        pub fn writer(self: *Self) GenericWriter.Writer {
            return self.generic_writer.writer();
        }
    };
}

test "GenericWriter" {
    var ta = TestAlloc{};
    defer ta.deinit(.Panic);
    errdefer ta.deinit(.NoPanic);
    const alloc = ta.alloc();

    var sw = StringWriter.init(alloc);
    var real_writer = sw.writer();
    var generic_writer_impl = GenericWriterImpl(@TypeOf(real_writer)){};
    generic_writer_impl.init(&real_writer);
    const generic_writer = generic_writer_impl.writer();

    try generic_writer.print("{} Hello {s}\n", .{1, "World"});
    try generic_writer.print("{} Hello {s}\n", .{2, "again"});

    const string = sw.get();
    try std.testing.expectEqualStrings(
        \\1 Hello World
        \\2 Hello again
        \\
        , string);
    alloc.free(string);
}

pub const GenericReader = struct {
    pub const GenericReaderError = error {
        GenericReaderError,
    };

    impl: *anyopaque,
    read_fn_impl: fn(impl: *anyopaque, bytes: []u8) GenericReaderError!usize,

    fn read_fn(self: *GenericReader, bytes: []u8) GenericReaderError!usize {
        return self.read_fn_impl(self.impl, bytes);
    }

    pub const Reader = std.io.Reader(*GenericReader, GenericReaderError, read_fn);

    pub fn reader(self: *GenericReader) Reader {
        return .{.context = self};
    }
};

pub fn GenericReaderImpl(comptime RealReader: type) type {
    return struct {
        const Self = @This();

        const GenericReaderError = GenericReader.GenericReaderError;

        real_reader: *RealReader = undefined,
        generic_reader: GenericReader = undefined,

        fn read_fn_impl(impl: *anyopaque, bytes: []u8) GenericReaderError!usize {
            const self = @ptrCast(*Self, @alignCast(@alignOf(RealReader), impl));
            return self.real_reader.read(bytes) catch GenericReaderError.GenericReaderError;
        }

        pub fn init(self: *Self, real_reader: *RealReader) void {
            self.* = .{
                .real_reader = real_reader,
                .generic_reader = .{
                    .impl = @ptrCast(*anyopaque, self),
                    .read_fn_impl = read_fn_impl,
                },
            };
        }

        pub fn reader(self: *Self) GenericReader.Reader {
            return self.generic_reader.reader();
        }
    };
}

test "GenericReader" {
    var ta = TestAlloc{};
    defer ta.deinit(.Panic);
    errdefer ta.deinit(.NoPanic);
    const alloc = ta.alloc();

    var sr = StringReader{.string = "Hello world!"};
    var real_reader = sr.reader();
    var generic_reader_impl = GenericReaderImpl(@TypeOf(real_reader)){};
    generic_reader_impl.init(&real_reader);
    const generic_reader = generic_reader_impl.reader();

    var store = std.ArrayList(u8).init(alloc);
    defer store.deinit();
    try generic_reader.readAllArrayList(&store, 16);
    const result = store.toOwnedSlice();
    defer alloc.free(result);
    try std.testing.expectEqualStrings("Hello world!", result);
}
