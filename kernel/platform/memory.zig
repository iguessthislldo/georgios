const kutil = @import("../util.zig");
const kmemory = @import("../memory.zig");
const KernelMemory = kmemory.Memory;
const RealMemoryMap = kmemory.RealMemoryMap;
const AllocError = kmemory.AllocError;
const FreeError = kmemory.FreeError;
const Range = kmemory.Range;
const print = @import("../print.zig");

const platform = @import("platform.zig");
const to_virtual = platform.kernel_to_virtual;

pub const frame_size = kutil.Ki(4);
const page_size = frame_size;
const pages_per_table = kutil.Ki(1);
const table_pages_size = page_size * pages_per_table;
const tables_per_directory = kutil.Ki(1);
const table_size = @sizeOf(u32) * pages_per_table;

export var page_directory: [tables_per_directory]u32
    align(frame_size) linksection(".data") = undefined;
export var kernel_page_tables: []u32 = undefined;
pub export var kernel_range_start_available: u32 = undefined;
export var kernel_page_table_count: u32 = 0;

pub inline fn get_address(dir_index: usize, table_index: usize) usize {
    return dir_index * table_pages_size + table_index * page_size;
}

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

pub inline fn get_table(dir_entry: u32) [*]allowzero u32 {
    return @intToPtr([*]allowzero u32, to_virtual(get_table_address(dir_entry)));
}

// fn get_table(address: u32) ?[*]u32 {
//     const dir_index = get_directory_index(address);
//     const dir_entry = page_directory[dir_index];
//     if (!table_is_present(dir_entry)) {
//         return null;
//     }
//     return ;
// }
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

pub inline fn present_entry(address: u32) u32 {
    return (address & 0xfffff000) | 1;
}

pub inline fn set_entry(entry: *allowzero u32, address: usize, user: bool) void {
    // TODO: Seperate User and Write
    entry.* = present_entry(address) | ((if (user) u32(0b11) else u32(0)) << 1);
}
// (End of Page Table Operations)

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
    const Self = @This();
    const FreeFramePtr = ?usize;

    extern var _VIRTUAL_LOW_START: u32;

    kernel_memory: *KernelMemory = undefined,
    next_free_frame: FreeFramePtr = null,
    kernel_tables_index_start: usize = 0,
    virtual_page_address: usize = 0,
    virtual_page_index: usize = 0,
    start_of_virtual_space: usize = 0,
    page_allocator: kmemory.Allocator = undefined,

    pub fn initialize(self: *Memory, kernel_memory: *KernelMemory,
            memory_map: *RealMemoryMap) void {
        self.kernel_memory = kernel_memory;
        self.page_allocator.alloc_impl = Self.page_alloc;
        self.page_allocator.free_impl = Self.page_free;
        kernel_memory.big_alloc = &self.page_allocator;
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

        self.start_of_virtual_space = kutil.align_up(
            @ptrToInt(kernel_page_tables.ptr) + kernel_page_tables.len * table_size,
            table_pages_size);
    }

    fn map_virtual_page(self: *Memory, address: usize) void {
        // print.format("map_virtual_page: {:a}\n", address);
        if (kernel_page_tables[self.virtual_page_index] != present_entry(address)) {
            set_entry(&kernel_page_tables[self.virtual_page_index], address, false);
            invalidate_page(self.virtual_page_address);
        }
    }

    pub fn push_frame(self: *Memory, frame: usize) void {
        // Map fixed virtual address to frame.
        self.map_virtual_page(frame);
        // Put the current next_free_frame into the frame.
        @intToPtr(*FreeFramePtr, self.virtual_page_address).* =
            self.next_free_frame;
        // Point to that frame.
        self.next_free_frame = frame;
    }

    pub fn pop_frame(self: *Memory) AllocError!usize {
        if (self.next_free_frame) |frame| {
            const prev = frame;
            // Map fixed virtual address to next_free_frame.
            self.map_virtual_page(frame);
            // Get the "next" next_free_frame from the contents of the current
            // one.
            self.next_free_frame =
                @intToPtr(*FreeFramePtr, self.virtual_page_address).*;
            // Return the previous next_free_frame
            return prev;
        }
        return AllocError.OutOfMemory;
    }

    fn get_unused_kernel_space(self: *Memory, requested_size: usize) AllocError!Range {
        // print.format("get_unused_kernel_space {:x}\n", requested_size);
        const start = self.start_of_virtual_space;
        const dir_index_start = get_directory_index(start);
        const table_index_start = get_table_index(start);
        var rv = Range{.size = kutil.align_up(requested_size, page_size)};
        var range = Range{};
        var dir_index: usize = dir_index_start;
        while (dir_index < tables_per_directory) {
            // print.format(" - Table {:x}\n", dir_index);
            const dir_offset = dir_index * table_pages_size;
            const dir_entry = page_directory[dir_index];
            if (!table_is_present(dir_entry)) {
                if (range.size == 0) {
                    range.start = dir_offset;
                }
                range.size += table_pages_size;
                if (range.size >= rv.size) {
                    rv.start = range.start;
                    return rv;
                }
                dir_index += 1;
                continue;
            }
            self.map_virtual_page(get_table_address(page_directory[dir_index]));
            const table = @intToPtr([*]allowzero u32, self.virtual_page_address);
            var table_index: usize =
                if (dir_index == dir_index_start) table_index_start else 0;
            while (table_index < pages_per_table) {
                // print.format(" - Page {:x}\n", table_index);
                if (page_is_present(table[table_index])) {
                    if (range.size > 0) {
                        range.size = 0;
                        range.start = 0;
                    }
                } else {
                    if (range.size == 0) {
                        range.start = dir_offset + table_index * page_size;
                    }
                    range.size += page_size;
                    if (range.size >= rv.size) {
                        rv.start = range.start;
                        return rv;
                    }
                }
                table_index += 1;
            }
            dir_index += 1;
        }
        return AllocError.OutOfMemory;
    }

    pub fn new_page_table(self: *Memory, dir_index: usize) AllocError!void {
        // print.format("new_page_table {:x}\n", dir_index);
        // TODO: Go through memory.Memory
        const table_address = try self.pop_frame();
        // TODO set_entry for page_directory
        set_entry(&page_directory[dir_index], table_address, false);
        self.map_virtual_page(table_address);
        const table = @intToPtr([*]u32, self.virtual_page_address);
        var i: usize = 0;
        while (i < pages_per_table) {
            table[i] = 0;
            i += 1;
        }
    }

    // TODO: Read/Write and Any Other Options
    fn mark_virtual_memory_present(
            self: *Memory, range: Range, user: bool) AllocError!void {
        // print.format("mark_virtual_memory_present {:a} {:a}\n", range.start, range.size);
        const dir_index_start = get_directory_index(range.start);
        const table_index_start = get_table_index(range.start);
        var dir_index: usize = dir_index_start;
        var marked: usize = 0;
        while (dir_index < tables_per_directory) {
            // print.format(" - Table {:x}\n", dir_index);
            const dir_offset = dir_index * table_pages_size;
            if (!table_is_present(page_directory[dir_index])) {
                try self.new_page_table(dir_index);
            }
            self.map_virtual_page(get_table_address(page_directory[dir_index]));
            if (user) {
                // TODO: Seperate User and Write
                page_directory[dir_index] |= (0b11 << 1);
            }
            const table = @intToPtr([*]u32, self.virtual_page_address);
            var table_index: usize =
                if (dir_index == dir_index_start) table_index_start else 0;
            while (table_index < pages_per_table) {
                // print.format(" - Page {:x} {:x} {:x}\n",
                //     dir_index, table_index, table[table_index]);
                if (page_is_present(table[table_index])) {
                    print.format("{:x}\n", get_address(dir_index, table_index));
                    @panic("mark_virtual_memory_present: Page already present!");
                }
                // TODO: Go through memory.Memory for pop_frame
                const frame = try self.pop_frame();
                self.map_virtual_page(get_table_address(page_directory[dir_index]));
                set_entry(&table[table_index], frame, user);
                invalidate_page(get_address(dir_index, table_index));
                marked += page_size;
                if (marked >= range.size) return;
                table_index += 1;
            }
            dir_index += 1;
        }
    }

    // fn mark_virtual_memory_absent(self: *Memory, range: Range) void {
    // }

    fn page_alloc(allocator: *kmemory.Allocator, size: usize) AllocError![]u8 {
        const self = @fieldParentPtr(Self, "page_allocator", allocator);
        const range = try self.get_unused_kernel_space(size);
        try self.mark_virtual_memory_present(range, false);
        return range.to_slice(u8);
    }

    fn page_free(allocator: *kmemory.Allocator, value: []u8) FreeError!void {
        const self = @fieldParentPtr(Self, "page_allocator", allocator);
        // TODO
    }
};
