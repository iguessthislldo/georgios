const std = @import("std");

const utils = @import("utils.zig");
const Error = utils.Error;

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
/// If `source.len > destination.len` then the copy is truncated.
pub fn memory_copy_truncate(destination: []u8, source: []const u8) callconv(.Inline) usize {
    const size = @minimum(destination.len, source.len);
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
            return @ptrCast([*]u8, value)[0.. @sizeOf(pointer_type.child) * count];
        },
        else => {
            @compileLog("Unsupported Type is ", @typeName(Type));
            @compileError("Unsupported Type");
        }
    }
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
            return @ptrCast([*]const u8, value)[0.. @sizeOf(pointer_type.child) * count];
        },
        else => {
            @compileLog("Unsupported Type is ", @typeName(Type));
            @compileError("Unsupported Type");
        }
    }
}

pub fn empty_slice(comptime Type: type, ptr: anytype) callconv(.Inline) []const Type {
    const PtrType = @TypeOf(ptr);
    var rv: []const Type = undefined;
    rv.len = 0;
    rv.ptr = switch (@typeInfo(PtrType)) {
        std.builtin.TypeId.Pointer => @ptrCast([*]const Type, ptr),
        std.builtin.TypeId.Int => @intToPtr([*]const Type, ptr),
        std.builtin.TypeId.ComptimeInt => @intToPtr([*]const Type, @as(usize, ptr)),
        else => {
            @compileLog("Unsupported Type is ", @typeName(PtrType));
            @compileError("Unsupported Type");
        }
    };
    return rv;
}

pub const TestAlloc = struct {
    impl: std.heap.GeneralPurposeAllocator(.{}) = .{},
    has_deinit: bool = false,

    pub fn alloc(self: *TestAlloc) std.mem.Allocator {
        return self.impl.allocator();
    }

    pub const ShouldPanic = enum {
        Panic,
        NoPanic,
    };

    pub fn deinit(self: *TestAlloc, should_panic: ShouldPanic) void {
        if (!self.has_deinit) {
            const leaks = self.impl.deinit();
            if (should_panic == .Panic) {
                std.testing.expect(!leaks) catch @panic("leak(s) detected");
            }
            self.has_deinit = true;
        }
    }
};

test "TestAlloc example usage" {
    var ta = utils.TestAlloc{};
    defer ta.deinit(.NoPanic);
    const alloc = ta.alloc();

    const int = try alloc.create(u32);
    int.* = 13;
    alloc.destroy(int);

    ta.deinit(.Panic);
}
