const kutil = @import("util.zig");
const print = @import("print.zig");
const platform = @import("platform/platform.zig");

const Error = error {
    OutOfMemory,
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

    /// Start of the range of memory that will be shared between the frame
    /// stack and a frame group.
    shared_range_start: usize = 0,

    /// Size of the range of memory that will be shared between the frame stack
    /// and a frame group.
    shared_range_size: usize = 0,

    fn invalid(self: *RealMemoryMap) bool {
        return
            self.frame_group_count == 0 or
            self.total_frame_count == 0 or
            self.shared_range_size == 0;
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
    /// fit in it. Return the frame count.
    fn add_frame_group(self: *RealMemoryMap, start: usize, end: usize) void {
        const aligned_start = kutil.align_up(start, platform.frame_size);
        const aligned_end = kutil.align_down(end, platform.frame_size);
        if (aligned_start < aligned_end) {
            self.add_frame_group_impl(aligned_start,
                (aligned_end - aligned_start) / platform.frame_size);
        }
    }

    /// Add range of contiguous real memory deemed usable.
    pub fn add_range(self: *RealMemoryMap, start: usize, size: usize) void {
        const end = start + size;
        const kernel_start = platform.kernel_real_start();
        const kernel_end = platform.kernel_real_end();
        if (start >= kernel_start and kernel_end <= end) {
            // See if we can fit any frames before the kernel.
            self.add_frame_group(start, kernel_start);

            // The area after the kernel is going to be shared by the frame
            // stack and a frame group. A calculation of the optimal proportion
            // between the two will be attempted in finalize().
            self.shared_range_start = kernel_end;
            self.shared_range_size = end - kernel_end;
        } else { // Range that will just be used for frames.
            self.add_frame_group(start, size);
        }
    }

    /// To be called by Memory.initialize()
    pub fn finalize(self: *RealMemoryMap) void {
        // Calculate layout of shared frame stack/frame group range.
        // Subtract a frame's worth of bytes so we can align the frame group.
        const effective_space = self.shared_range_size - platform.frame_size;
        const ptr_size = @sizeOf(usize);
        // Size taken by frame stack pointers for "other" frame groups
        const other_ptr_size = ptr_size * self.total_frame_count;
        // The number of frames we can fit here
        const this_frame_group_count = (effective_space - other_ptr_size) /
            (ptr_size + platform.frame_size);
        // Now add this frame group.
        const this_frame_group_size =
            this_frame_group_count * platform.frame_size;
        const shared_range_end =
            self.shared_range_start + self.shared_range_size;
        const this_frame_group_start =
            shared_range_end - this_frame_group_size;
        self.add_frame_group(this_frame_group_start, shared_range_end);
        // This isn't perfect, In the first run it left about 6KiB between the
        // frame stack and the frames. I was hoping for less than 4KiB, but
        // close enough...
    }
};

/// Used by the kernel to manage system memory
pub const Memory = struct {
    /// To be called by the platform after it can give "map".
    pub fn initialize(self: *Memory, map: *RealMemoryMap) void {
        print.format(
            \\ - Initializing Memory System
            \\   - Start of kernel: {:x}
            \\   - End of kernel: {:x}
            \\   - Size of kernel is {} B ({} KiB)
            \\   - Frame Size: {} B ({} KiB)
            \\
            ,
            platform.kernel_virtual_start(),
            platform.kernel_virtual_end(),
            platform.kernel_size(),
            platform.kernel_size() >> 10,
            platform.frame_size,
            platform.frame_size >> 10);

        // Process RealMemoryMap
        if (map.invalid()) {
            @panic("ReadMemoryMap is invalid!");
        }
        map.finalize();
        print.string("   - Frame Groups:\n");
        for (map.frame_groups[0..map.frame_group_count]) |*i| {
            print.format("     - {} Frames starting at {:x} \n",
                i.frame_count, i.start);
        }
        const total_memory: usize = map.total_frame_count * platform.frame_size;
        print.format(
            "   - Total Allocatable Memory: {} ({} KiB/{} MiB/{} GiB)\n",
            total_memory,
            total_memory >> 10,
            total_memory >> 20,
            total_memory >> 30);

        // TODO: Initialize Frame Stack
    }

    // TODO: Real Memory Management
    // TODO: Virtual Memory Management
};
