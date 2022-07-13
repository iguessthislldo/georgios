const std = @import("std");

const georgios = @import("georgios");
const utils = @import("utils");

const kernel = @import("kernel.zig");
const print = @import("print.zig");
const BuddyAllocator = @import("buddy_allocator.zig").BuddyAllocator;

const platform = @import("platform.zig");

pub const AllocError = georgios.memory.AllocError;
pub const FreeError = georgios.memory.FreeError;
pub const MemoryError = georgios.memory.MemoryError;

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
        return utils.make_slice(Type, self.to_ptr([*]Type), self.size / @sizeOf(Type));
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
        const aligned_start = utils.align_up(start, platform.frame_size);
        const aligned_end = utils.align_down(end, platform.frame_size);
        if (aligned_start < aligned_end) {
            self.add_frame_group_impl(aligned_start,
                (aligned_end - aligned_start) / platform.frame_size);
        }
    }
};

var alloc_debug = false;
pub const Allocator = struct {
    alloc_impl: fn(*Allocator, usize, usize) AllocError![]u8,
    free_impl: fn(*Allocator, []const u8, usize) FreeError!void,

    pub fn alloc(self: *Allocator, comptime Type: type) AllocError!*Type {
        if (alloc_debug) print.string(
            "Allocator.alloc: " ++ @typeName(Type) ++ "\n");
        const rv = @ptrCast(*Type, @alignCast(
            @alignOf(Type), (try self.alloc_impl(self, @sizeOf(Type), @alignOf(Type))).ptr));
        if (alloc_debug) print.format(
            "Allocator.alloc: " ++ @typeName(Type) ++ ": {:a}\n", .{@ptrToInt(rv)});
        return rv;
    }

    pub fn free(self: *Allocator, value: anytype) FreeError!void {
        const traits = @typeInfo(@TypeOf(value)).Pointer;
        const bytes = utils.to_bytes(value);
        if (alloc_debug) print.format("Allocator.free: " ++ @typeName(@TypeOf(value)) ++
            ": {:a}\n", .{@ptrToInt(bytes.ptr)});
        try self.free_impl(self, bytes, traits.alignment);
    }

    pub fn alloc_array(
            self: *Allocator, comptime Type: type, count: usize) AllocError![]Type {
        if (alloc_debug) print.format(
            "Allocator.alloc_array: [{}]" ++ @typeName(Type) ++ "\n", .{count});
        if (count == 0) {
            return AllocError.ZeroSizedAlloc;
        }
        const rv = @ptrCast([*]Type, @alignCast(@alignOf(Type),
            (try self.alloc_impl(self, @sizeOf(Type) * count, @alignOf(Type))).ptr))[0..count];
        if (alloc_debug) print.format("Allocator.alloc_array: [{}]" ++ @typeName(Type) ++
            ": {:a}\n", .{count, @ptrToInt(rv.ptr)});
        return rv;
    }

    pub fn free_array(self: *Allocator, array: anytype) FreeError!void {
        const traits = @typeInfo(@TypeOf(array)).Pointer;
        if (alloc_debug) print.format(
            "Allocator.free_array: [{}]" ++ @typeName(traits.child) ++ ": {:a}\n",
            .{array.len, @ptrToInt(array.ptr)});
        try self.free_impl(self, utils.to_const_bytes(array), traits.alignment);
    }

    pub fn alloc_range(self: *Allocator, size: usize) AllocError!Range {
        if (alloc_debug) print.format("Allocator.alloc_range: {}\n", .{size});
        if (size == 0) {
            return AllocError.ZeroSizedAlloc;
        }
        const rv = Range{
            .start = @ptrToInt((try self.alloc_impl(self, size, 1)).ptr), .size = size};
        if (alloc_debug) print.format("Allocator.alloc_range: {}: {:a}\n", .{size, rv.start});
        return rv;
    }

    pub fn free_range(self: *Allocator, range: Range) FreeError!void {
        if (alloc_debug) print.format(
            "Allocator.free_range: {}: {:a}\n", .{range.size, range.start});
        try self.free_impl(self, range.to_slice(u8), 1);
    }

    fn std_alloc(self: *Allocator, n: usize, ptr_align: u29, len_align: u29, ra: usize) ![]u8 {
        _ = len_align;
        _ = ra;
        return self.alloc_impl(self, n, ptr_align) catch return std.mem.Allocator.Error.OutOfMemory;
    }

    fn std_resize(self: *Allocator, buf: []u8, buf_align: u29, new_len: usize, len_align: u29,
            ret_addr: usize) ?usize {
        _ = self;
        _ = buf;
        _ = buf_align;
        _ = new_len;
        _ = len_align;
        _ = ret_addr;
        @panic("Allocator.std_resize called!");
    }

    fn std_free(self: *Allocator, buf: []u8, buf_align: u29, ret_addr: usize) void {
        _ = ret_addr;
        self.free_impl(self, buf, buf_align) catch return;
    }

    pub fn std_allocator(self: *Allocator) std.mem.Allocator {
        return std.mem.Allocator.init(self, std_alloc, std_resize, std_free);
    }
};

pub const UnitTestAllocator = struct {
    const Self = @This();

    const Impl = std.heap.ArenaAllocator;

    allocator: Allocator = undefined,
    impl: Impl = undefined,
    allocated: usize = undefined,

    pub fn init(self: *Self) void {
        self.impl = Impl.init(std.heap.page_allocator);
        self.allocator.alloc_impl = Self.alloc;
        self.allocator.free_impl = Self.free;
        self.allocated = 0;
    }

    pub fn done_no_checks(self: *Self) void {
        self.impl.deinit();
    }

    pub fn done(self: *Self) void {
        std.testing.expectEqual(@as(usize, 0), self.allocated)
            catch @panic("outstanding allocations or wrong sizes");
        self.done_no_checks();
    }

    pub fn done_check_if(self: *Self, condition: *bool) void {
        if (condition.*) {
            self.done();
        } else {
            self.done_no_checks();
        }
    }

    pub fn alloc(allocator: *Allocator, size: usize, align_to: usize) AllocError![]u8 {
        const self = @fieldParentPtr(Self, "allocator", allocator);
        self.allocated += size;

        const align_u29 = @truncate(u29, align_to);
        const rv = self.impl.allocator().allocBytes(align_u29, size,
            align_u29, @returnAddress()) catch return AllocError.OutOfMemory;
        // std.debug.print("alloc {x}: {}\n", .{@ptrToInt(rv.ptr), rv.len});
        return rv;
    }

    pub fn free(allocator: *Allocator, value: []const u8, aligned_to: usize) FreeError!void {
        // std.debug.print("free {x}: {}\n", .{@ptrToInt(value.ptr), value.len});
        const self = @fieldParentPtr(Self, "allocator", allocator);
        std.testing.expectEqual(true, self.allocated >= value.len)
            catch @panic("free arg is bigger than allocated sum");
        self.allocated -= value.len;
        _ = self.impl.allocator().rawFree(
            @intToPtr([*]u8, @ptrToInt(value.ptr))[0..value.len],
            @truncate(u29, aligned_to), @returnAddress());
    }
};

/// Used by the kernel to manage system memory
pub const Manager = struct {
    const alloc_size = utils.Mi(1);
    const AllocImplType = BuddyAllocator(alloc_size);

    impl: platform.MemoryMgrImpl = .{},
    free_frame_count: usize = 0,
    alloc_range: Range = undefined,
    alloc_impl_range: Range = undefined,
    alloc_impl: *AllocImplType = undefined,
    alloc: *Allocator = undefined,
    big_alloc: *Allocator = undefined,

    /// To be called by the platform after it can give "map".
    pub fn init(self: *Manager, map: *RealMemoryMap) !void {
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
        self.impl.init(self, map);

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

        self.alloc_impl = try self.big_alloc.alloc(AllocImplType);
        try self.alloc_impl.init(try self.big_alloc.alloc([alloc_size]u8));
        self.alloc = &self.alloc_impl.allocator;
        kernel.alloc = self.alloc;
        kernel.big_alloc = self.big_alloc;
    }

    pub fn free_pmem(self: *Manager, frame: usize) void {
        self.impl.push_frame(frame);
        self.free_frame_count += 1;
    }

    pub fn alloc_pmem(self: *Manager) AllocError!usize {
        const frame = try self.impl.pop_frame();
        self.free_frame_count -= 1;
        return frame;
    }
};
