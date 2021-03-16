const std = @import("std");

const util = @import("util.zig");
const print = @import("print.zig");
const BuddyAllocator = @import("buddy_allocator.zig").BuddyAllocator;

const platform = @import("platform.zig");
const PlatformMemory = platform.Memory;

pub const AllocError = error {
    OutOfMemory,
};
pub const FreeError = error {
    InvalidFree,
};
pub const MemoryError = AllocError || FreeError;

pub const Range = struct {
    start: usize = 0,
    size: usize = 0,

    pub fn from_bytes(bytes: []const u8) Range {
        return .{.start = @ptrToInt(bytes.ptr), .size = bytes.len};
    }

    pub fn end(self: *const Range) usize {
        return self.start + self.size;
    }

    pub fn to_ptr(self: *const Range, comptime PtrType: type) PtrType {
        return @intToPtr(PtrType, self.start);
    }

    pub fn to_slice(self: *const Range, comptime Type: type) []Type {
        return util.make_slice(Type, self.to_ptr([*]Type), self.size / @sizeOf(Type));
    }
};

/// Used by the platform to provide what real memory can be used for the real
/// memory allocator.
pub const RealMemoryMap = struct {
    const FrameGroup = struct {
        start: usize,
        frame_count: usize,
    };
    frame_groups: [64]FrameGroup = undefined,
    frame_group_count: usize = 0,
    total_frame_count: usize = 0,

    fn invalid(self: *RealMemoryMap) bool {
        return
            self.frame_group_count == 0 or
            self.total_frame_count == 0;
    }

    /// Directly add a frame group.
    fn add_frame_group_impl(self: *RealMemoryMap,
            start: usize, frame_count: usize) void {
        if ((self.frame_group_count + 1) >= self.frame_groups.len) {
            @panic("Too many frame groups!");
        }
        self.frame_groups[self.frame_group_count] = FrameGroup{
            .start = start,
            .frame_count = frame_count,
        };
        self.frame_group_count += 1;
        self.total_frame_count += frame_count;
    }

    /// Given a memory range, add a frame group if there are frames that can
    /// fit in it.
    pub fn add_frame_group(self: *RealMemoryMap, start: usize, end: usize) void {
        const aligned_start = util.align_up(start, platform.frame_size);
        const aligned_end = util.align_down(end, platform.frame_size);
        if (aligned_start < aligned_end) {
            self.add_frame_group_impl(aligned_start,
                (aligned_end - aligned_start) / platform.frame_size);
        }
    }
};

var alloc_debug = false;
pub const Allocator = struct {
    alloc_impl: fn(self: *Allocator, size: usize) AllocError![]u8,
    free_impl: fn(self: *Allocator, value: []u8) FreeError!void,

    pub fn alloc(self: *Allocator, comptime Type: type) AllocError!*Type {
        if (alloc_debug) print.string(
            "Allocator.alloc: " ++ @typeName(Type) ++ "\n");
        const rv = @ptrCast(*Type, @alignCast(
            @alignOf(Type), (try self.alloc_impl(self, @sizeOf(Type))).ptr));
        if (alloc_debug) print.format(
            "Allocator.alloc: " ++ @typeName(Type) ++ ": {:a}\n", .{@ptrToInt(rv)});
        return rv;
    }

    pub fn free(self: *Allocator, value: anytype) FreeError!void {
        const bytes = util.to_bytes(value);
        if (alloc_debug) print.format("Allocator.free: " ++ @typeName(@TypeOf(value)) ++
            ": {:a}\n", .{@ptrToInt(bytes.ptr)});
        try self.free_impl(self, bytes);
    }

    pub fn alloc_array(
            self: *Allocator, comptime Type: type, count: usize) AllocError![]Type {
        if (alloc_debug) print.format(
            "Allocator.alloc_array: [{}]" ++ @typeName(Type) ++ "\n", .{count});
        const rv = @ptrCast([*]Type, @alignCast(@alignOf(Type),
            (try self.alloc_impl(self, @sizeOf(Type) * count)).ptr))[0..count];
        if (alloc_debug) print.format("Allocator.alloc_array: [{}]" ++ @typeName(Type) ++
            ": {:a}\n", .{count, @ptrToInt(rv.ptr)});
        return rv;
    }

    pub fn free_array(self: *Allocator, array: anytype) FreeError!void {
        const traits = @typeInfo(@TypeOf(array)).Pointer;
        if (alloc_debug) print.format(
            "Allocator.free_array: [{}]" ++ @typeName(traits.child) ++ ": {:a}\n",
            .{array.len, @ptrToInt(array.ptr)});
        try self.free_impl(self, std.mem.sliceAsBytes(array));
    }

    pub fn alloc_range(self: *Allocator, size: usize) AllocError!Range {
        if (alloc_debug) print.format("Allocator.alloc_range: {}\n", .{size});
        const rv = Range{
            .start = @ptrToInt((try self.alloc_impl(self, size)).ptr), .size = size};
        if (alloc_debug) print.format("Allocator.alloc_range: {}: {:a}\n", .{size, rv.start});
        return rv;
    }

    pub fn free_range(self: *Allocator, range: Range) FreeError!void {
        if (alloc_debug) print.format(
            "Allocator.free_range: {}: {:a}\n", .{range.size, range.start});
        try self.free_impl(self, range.to_slice(u8));
    }
};

pub const UnitTestAllocator = struct {
    const Self = @This();

    const Impl = std.heap.ArenaAllocator;

    allocator: Allocator = undefined,
    impl: Impl = undefined,
    allocated: usize = undefined,

    pub fn initialize(self: *Self) void {
        self.impl = Impl.init(std.heap.page_allocator);
        self.allocator.alloc_impl = Self.alloc;
        self.allocator.free_impl = Self.free;
        self.allocated = 0;
    }

    pub fn done(self: *Self) void {
        std.testing.expectEqual(@as(usize, 0), self.allocated);
        self.impl.deinit();
    }

    pub fn alloc(allocator: *Allocator, size: usize) AllocError![]u8 {
        const self = @fieldParentPtr(Self, "allocator", allocator);
        self.allocated += size;
        return self.impl.allocator.alloc(u8, size) catch return AllocError.OutOfMemory;
    }

    pub fn free(allocator: *Allocator, value: []u8) FreeError!void {
        const self = @fieldParentPtr(Self, "allocator", allocator);
        std.testing.expectEqual(true, self.allocated >= value.len);
        self.allocated -= value.len;
        self.impl.allocator.free(value);
    }
};

/// Used by the kernel to manage system memory
pub const Memory = struct {
    const small_alloc_size = util.Mi(1);
    const SmallAllocImplType = BuddyAllocator(small_alloc_size);

    platform_memory: PlatformMemory = PlatformMemory{},
    free_frame_count: usize = 0,
    small_alloc_range: Range = undefined,
    small_alloc_impl_range: Range = undefined,
    small_alloc_impl: *SmallAllocImplType = undefined,
    small_alloc: *Allocator = undefined,
    big_alloc: *Allocator = undefined,

    /// To be called by the platform after it can give "map".
    pub fn initialize(self: *Memory, map: *RealMemoryMap) !void {
        print.debug_format(
            \\ - Initializing Memory System
            \\   - Start of kernel:
            \\      - Real:    {:a}
            \\      - Virtual: {:a}
            \\   - End of kernel:
            \\      - Real:    {:a}
            \\      - Virtual: {:a}
            \\   - Size of kernel is {} B ({} KiB)
            \\   - Frame Size: {} B ({} KiB)
            \\
            , .{
            platform.kernel_real_start(),
            platform.kernel_virtual_start(),
            platform.kernel_real_end(),
            platform.kernel_virtual_end(),
            platform.kernel_size(),
            platform.kernel_size() >> 10,
            platform.frame_size,
            platform.frame_size >> 10});

        // Process RealMemoryMap
        if (map.invalid()) {
            @panic("RealMemoryMap is invalid!");
        }
        print.debug_string("   - Frame Groups:\n");
        for (map.frame_groups[0..map.frame_group_count]) |*i| {
            print.debug_format("     - {} Frames starting at {:a} \n",
                .{i.frame_count, i.start});
        }

        // Initialize Platform Implementation
        // After this we should be able to manage all the memory on the system.
        self.platform_memory.initialize(self, map);

        // List Memory
        const total_memory: usize = map.total_frame_count * platform.frame_size;
        const indent = if (print.debug_print) "   - " else "";
        print.format(
            "{}Total Available Memory: {} B ({} KiB/{} MiB/{} GiB)\n", .{
            indent,
            total_memory,
            total_memory >> 10,
            total_memory >> 20,
            total_memory >> 30});

        self.small_alloc_impl = try self.big_alloc.alloc(SmallAllocImplType);
        self.small_alloc_impl.initialize(@ptrToInt(try self.big_alloc.alloc([small_alloc_size]u8)));
        self.small_alloc = &self.small_alloc_impl.allocator;
    }

    pub fn free_pmem(self: *Memory, frame: usize) void {
        self.platform_memory.push_frame(frame);
        self.free_frame_count += 1;
    }

    pub fn alloc_pmem(self: *Memory) AllocError!usize {
        const frame = try self.platform_memory.pop_frame();
        self.free_frame_count -= 1;
        return frame;
    }
};
