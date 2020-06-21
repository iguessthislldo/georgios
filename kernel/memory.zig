const kutil = @import("util.zig");
const print = @import("print.zig");

const platform = @import("platform.zig");
const PlatformMemory = platform.Memory;

pub const MemoryError = error {
    OutOfMemory,
    InvalidPointerArgument,
};

pub const Range = struct {
    start: usize = 0,
    size: usize = 0,

    pub fn end(self: *Range) usize {
        return self.start + self.size;
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
    fn add_frame_group(self: *RealMemoryMap, start: usize, end: usize) void {
        const aligned_start = kutil.align_up(start, platform.frame_size);
        const aligned_end = kutil.align_down(end, platform.frame_size);
        if (aligned_start < aligned_end) {
            self.add_frame_group_impl(aligned_start,
                (aligned_end - aligned_start) / platform.frame_size);
        }
    }
};

/// Used by the kernel to manage system memory
pub const Memory = struct {
    platform_memory: PlatformMemory = PlatformMemory{},
    free_frame_count: usize = 0,

    /// To be called by the platform after it can give "map".
    pub fn initialize(self: *Memory, map: *RealMemoryMap) void {
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
            ,
            platform.kernel_real_start(),
            platform.kernel_virtual_start(),
            platform.kernel_real_end(),
            platform.kernel_virtual_end(),
            platform.kernel_size(),
            platform.kernel_size() >> 10,
            platform.frame_size,
            platform.frame_size >> 10);

        // Process RealMemoryMap
        if (map.invalid()) {
            @panic("RealMemoryMap is invalid!");
        }
        print.debug_string("   - Frame Groups:\n");
        for (map.frame_groups[0..map.frame_group_count]) |*i| {
            print.debug_format("     - {} Frames starting at {:a} \n",
                i.frame_count, i.start);
        }

        // Initialize Platform Implementation
        // After this we should be able to manage all the memory on the system.
        self.platform_memory.initialize(self, map);

        // List Memory
        const total_memory: usize = map.total_frame_count * platform.frame_size;
        print.format(
            "{}Total Available Memory: {} B ({} KiB/{} MiB/{} GiB)\n",
            if (print.debug_print) "   - " else "",
            total_memory,
            total_memory >> 10,
            total_memory >> 20,
            total_memory >> 30);
    }

    pub fn free_pmem(self: *Memory, frame: usize) void {
        self.platform_memory.push_frame(frame);
        self.free_frame_count += 1;
    }

    pub fn alloc_pmem(self: *Memory) MemoryError!usize {
        const frame = try self.platform_memory.pop_frame();
        self.free_frame_count -= 1;
        return frame;
    }

    // TODO: Virtual Memory Management
    // pub fn alloc_vmem(self: *Memory, what: Range) MemoryError!void {
    // }

    // pub fn free_vmem(self: *Memory, what: Range) MemoryError!void {
    // }
};

pub const Allocator = struct {
    alloc_impl: fn(self: *Allocator, size: usize) MemoryError!usize,
    free_impl: fn(self: *Allocator, address: usize) MemoryError!void,

    pub fn alloc(self: *Allocator, comptime Type: type) MemoryError!*Type {
        return @intToPtr(*Type, try self.alloc_impl(self, @sizeOf(Type)));
    }

    pub fn free(self: *Allocator, comptime Type: type, address: *Type) MemoryError!void {
        return self.free_impl(self, @ptrToInt(address));
    }
};
