const kutil = @import("../util.zig");
const kmemory = @import("../memory.zig");
const KernelMemory = kmemory.Memory;
const RealMemoryMap = kmemory.RealMemoryMap;
const MemoryError = kmemory.MemoryError;
const Range = kmemory.Range;
const print = @import("../print.zig");

const platform = @import("platform.zig");
const to_virtual = platform.kernel_to_virtual;

pub const frame_size = kutil.Ki(4);
const pages_per_table = kutil.Ki(1);
const table_size = frame_size * pages_per_table;
const tables_per_directory = kutil.Ki(1);

export var page_directory: [tables_per_directory]u32
    align(frame_size) linksection(".data") = undefined;
export var kernel_page_tables: []u32 = undefined;
pub export var kernel_range_start_available: u32 = undefined;
export var kernel_page_table_count: u32 = 0;

// Page Directory Operations
pub inline fn get_directory_index(address: u32) u32 {
    return (address & 0xffc00000) >> 22;
}

pub inline fn table_is_present(entry: u32) bool {
    return (entry & 1) == 1;
}

pub inline fn get_table_address(entry: u32) u32 {
    return entry & 0xfffff000;
}
// (End of Page Directory Operations)

// Page Table Operations
pub inline fn get_table_index(address: u32) u32 {
    return (address & 0x003ff000) >> 12;
}

pub inline fn page_is_present(entry: u32) bool {
    return (entry & 1) == 1;
}

pub inline fn get_page_address(entry: u32) u32 {
    return entry & 0xfffff000;
}
// (End of Page Table Operations)

pub inline fn get_page_offset(address: u32) u32 {
    return entry & 0xfff;
}

pub fn invalidate_page(address: u32) void {
    asm volatile ("invlpg (%[address])" : : [address] "{eax}" (address));
}

pub fn unmap_low_kernel() void {
    for (page_directory[0..kernel_page_table_count]) |*ptr| {
        ptr.* = 0;
    }
}

/// Add Frame Groups to Our Memory Map from Multiboot Memory Map
pub fn process_multiboot2_mmap(map: *RealMemoryMap, tag: *const Range) void {
    const entry_size = @intToPtr(*u32, tag.start + 8).*;
    const entries_end = tag.start + tag.size;
    var entry_ptr = tag.start + 16;
    while (entry_ptr < entries_end) : (entry_ptr += entry_size) {
        if (@intToPtr(*u32, entry_ptr + 16).* == 1) {
            var range_start = @intCast(usize, @intToPtr(*u64, entry_ptr).*);
            var range_size = @intCast(usize, @intToPtr(*u64, entry_ptr + 8).*);
            var contains_frame_stack = false;
            const range_end = range_start + range_size;
            if (range_start >= platform.kernel_real_start() and
                    platform.kernel_real_end() <= range_end) {
                range_size = range_end - kernel_range_start_available;
                range_start = kernel_range_start_available;
            }
            map.add_frame_group(range_start, range_size);
        }
    }
}

/// Kernel Memory System Platform Implementation
///
/// Physical Memory Allocation is based on
/// http://ethv.net/workshops/osdev/notes/notes-2
/// When a physical frame isn't being used it is part of a linked list.
pub const Memory = struct {
    const FreeFramePtr = ?usize;

    extern var _VIRTUAL_LOW_START: u32;

    kernel_memory: *KernelMemory = undefined,
    next_free_frame: FreeFramePtr = null,
    kernel_tables_index_start: usize = 0,
    virtual_page_address: usize = 0,
    virtual_page_index: usize = 0,

    pub fn initialize(self: *Memory, kernel_memory: *KernelMemory,
            memory_map: *RealMemoryMap) void {
        self.kernel_memory = kernel_memory;
        self.virtual_page_address = @ptrToInt(&_VIRTUAL_LOW_START);
        self.virtual_page_index = get_table_index(self.virtual_page_address);

        // Unmap low kernel left over from the start. We don't need it anymore
        // and we can recycle the memory.
        unmap_low_kernel();

        // var total_count: usize = 0;
        for (memory_map.frame_groups[0..memory_map.frame_group_count]) |*i| {
            // total_count += i.frame_count;
            var frame: usize = 0;
            while (frame < i.frame_count) {
                self.push_frame(i.start + frame * frame_size);
                frame += 1;
            }
        }

        // var counted: usize = 0;
        // while (true) {
        //     _ = self.pop_frame() catch break;
        //     counted += 1;
        // }
        // print.format("total_count: {}, counted: {}\n", total_count, counted);
    }

    pub fn push_frame(self: *Memory, frame: usize) void {
        // Map fixed virtual address to frame.
        kernel_page_tables[self.virtual_page_index] = frame + 1;
        invalidate_page(self.virtual_page_address);
        // Put the current next_free_frame into the frame.
        @intToPtr(*FreeFramePtr, self.virtual_page_address).* =
            self.next_free_frame;
        kernel_page_tables[self.virtual_page_index] = 0;
        invalidate_page(self.virtual_page_address);
        // Point to that frame.
        self.next_free_frame = frame;
    }

    pub fn pop_frame(self: *Memory) MemoryError!usize {
        if (self.next_free_frame) |frame| {
            const prev = frame;
            // Map fixed virtual address to next_free_frame.
            kernel_page_tables[self.virtual_page_index] = frame + 1;
            invalidate_page(self.virtual_page_address);
            // Get the "next" next_free_frame from the contents of the current
            // one.
            self.next_free_frame =
                @intToPtr(*FreeFramePtr, self.virtual_page_address).*;
            kernel_page_tables[self.virtual_page_index] = 0;
            invalidate_page(self.virtual_page_address);
            // Return the previous next_free_frame
            return prev;
        }
        return MemoryError.OutOfMemory;
    }
};
