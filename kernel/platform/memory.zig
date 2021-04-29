const std = @import("std");
const sliceAsBytes = std.mem.sliceAsBytes;

const utils = @import("utils");
const kmemory = @import("../memory.zig");
const KernelMemory = kmemory.Memory;
const RealMemoryMap = kmemory.RealMemoryMap;
const AllocError = kmemory.AllocError;
const FreeError = kmemory.FreeError;
const Range = kmemory.Range;
const print = @import("../print.zig");

const platform = @import("platform.zig");
const to_virtual = platform.kernel_to_virtual;

pub const frame_size = utils.Ki(4);
pub const page_size = frame_size;
const pages_per_table = utils.Ki(1);
const table_pages_size = page_size * pages_per_table;
const tables_per_directory = utils.Ki(1);
const table_size = @sizeOf(u32) * pages_per_table;

export var active_page_directory: [tables_per_directory]u32
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

extern var _VIRTUAL_OFFSET: u32;
pub inline fn get_kernel_space_start_directory_index() u32 {
    return get_directory_index(@ptrToInt(&_VIRTUAL_OFFSET));
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
    entry.* = present_entry(address) | (if (user) @as(u32, 0b110) else @as(u32, 0));
}
// (End of Page Table Operations)

pub fn invalidate_page(address: u32) void {
    asm volatile ("invlpg (%[address])" : : [address] "{eax}" (address));
}

pub fn reload_active_page_directory() void {
    asm volatile (
        \\ movl $low_page_directory, %%eax
        \\ movl %%eax, %%cr3
    :::
        "eax"
    );
}

pub fn load_page_directory(new: []const u32, old: ?[]u32) utils.Error!void {
    const end = get_kernel_space_start_directory_index();
    if (old) |o| {
        _ = try utils.memory_copy_error(
            sliceAsBytes(o[0..end]), sliceAsBytes(active_page_directory[0..end]));
    }
    _ = try utils.memory_copy_error(
        sliceAsBytes(active_page_directory[0..end]), sliceAsBytes(new[0..end]));
    reload_active_page_directory();
}

pub fn unmap_low_kernel() void {
    for (active_page_directory[0..kernel_page_table_count]) |*ptr| {
        ptr.* = 0;
    }
    reload_active_page_directory();
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
                // This is the kernel, remove it from the range.
                range_size = range_end - kernel_range_start_available;
                range_start = kernel_range_start_available;
            }
            if (range_start < frame_size) {
                // This is the Real Mode IVT and BDA, remove it from the range.
                range_start = frame_size;
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

    pub fn init(self: *Memory, kernel_memory: *KernelMemory,
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

        self.start_of_virtual_space = utils.align_up(
            @ptrToInt(kernel_page_tables.ptr) + kernel_page_tables.len * table_size,
            table_pages_size);
    }

    pub fn map_virtual_page(self: *Memory, address: usize) void {
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

    pub fn get_unused_kernel_space(self: *Memory, requested_size: usize) AllocError!Range {
        // print.format("get_unused_kernel_space {:x}\n", requested_size);
        const start = self.start_of_virtual_space;
        const dir_index_start = get_directory_index(start);
        const table_index_start = get_table_index(start);
        var rv = Range{.size = utils.align_up(requested_size, page_size)};
        var range = Range{};
        var dir_index: usize = dir_index_start;
        while (dir_index < tables_per_directory) {
            // print.format(" - Table {:x}\n", dir_index);
            const dir_offset = dir_index * table_pages_size;
            const dir_entry = active_page_directory[dir_index];
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
            self.map_virtual_page(get_table_address(active_page_directory[dir_index]));
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

    pub fn new_page_table(self: *Memory, page_directory: []u32,
            dir_index: usize, user: bool) AllocError!void {
        // print.format("new_page_table {:x}\n", dir_index);
        // TODO: Go through memory.Memory
        const table_address = try self.pop_frame();
        // TODO set_entry for page_directory
        set_entry(&page_directory[dir_index], table_address, user);
        self.map_virtual_page(table_address);
        const table = @intToPtr([*]u32, self.virtual_page_address);
        var i: usize = 0;
        while (i < pages_per_table) {
            table[i] = 0;
            i += 1;
        }
    }

    // TODO: Read/Write and Any Other Options
    pub fn mark_virtual_memory_present(
            self: *Memory, page_directory: []u32, range: Range, user: bool) AllocError!void {
        // print.format("mark_virtual_memory_present {:a} {:a}\n", range.start, range.size);
        const dir_index_start = get_directory_index(range.start);
        const table_index_start = get_table_index(range.start);
        var dir_index: usize = dir_index_start;
        var marked: usize = 0;
        while (dir_index < tables_per_directory) {
            // print.format(" - Table {:x}\n", dir_index);
            if (!table_is_present(page_directory[dir_index])) {
                try self.new_page_table(page_directory, dir_index, user);
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
                    print.format("{:x}\n", .{get_address(dir_index, table_index)});
                    @panic("mark_virtual_memory_present: Page already present!");
                }
                // TODO: Go through memory.Memory for pop_frame
                const frame = try self.pop_frame();
                self.map_virtual_page(get_table_address(page_directory[dir_index]));
                set_entry(&table[table_index], frame, user);
                if (&page_directory[0] == &active_page_directory[0]) {
                    invalidate_page(get_address(dir_index, table_index));
                }
                marked += page_size;
                if (marked >= range.size) return;
                table_index += 1;
            }
            dir_index += 1;
        }
    }

    // TODO
    fn mark_virtual_memory_absent(self: *Memory, range: Range) void {
    }

    fn page_alloc(allocator: *kmemory.Allocator, size: usize) AllocError![]u8 {
        const self = @fieldParentPtr(Self, "page_allocator", allocator);
        const range = try self.get_unused_kernel_space(size);
        try self.mark_virtual_memory_present(active_page_directory[0..], range, false);
        return range.to_slice(u8);
    }

    fn page_free(allocator: *kmemory.Allocator, value: []const u8) FreeError!void {
        const self = @fieldParentPtr(Self, "page_allocator", allocator);
        // TODO
    }

    pub fn new_page_directory(self: *Memory) AllocError![]u32 {
        const end = get_kernel_space_start_directory_index();
        const page_directory =
            try self.kernel_memory.big_alloc.alloc_array(u32, tables_per_directory);
        _ = utils.memory_set(sliceAsBytes(page_directory[0..]), 0);
        return page_directory;
    }

    pub fn page_directory_memory_copy(self: *Memory, page_directory: []u32,
            address: usize, data: []const u8) AllocError!void {
        // print.format("page_directory_memory_copy: {} b to {:a}\n", .{data.len, address});
        const dir_index_start = get_directory_index(address);
        const table_index_start = get_table_index(address);
        var dir_index: usize = dir_index_start;
        var data_left = data;
        var page_offset = address % page_size;
        while (data_left.len > 0 and dir_index < tables_per_directory) {
            if (!table_is_present(page_directory[dir_index])) {
                try self.new_page_table(page_directory, dir_index, true);
            }
            var table_index: usize =
                if (dir_index == dir_index_start) table_index_start else 0;
            while (data_left.len > 0 and table_index < pages_per_table) {
                self.map_virtual_page(get_table_address(page_directory[dir_index]));
                const table = @intToPtr([*]u32, self.virtual_page_address);
                if (!page_is_present(table[table_index])) {
                    // TODO: Go through memory.Memory for pop_frame
                    const frame = try self.pop_frame();
                    self.map_virtual_page(get_table_address(page_directory[dir_index]));
                    set_entry(&table[table_index], frame, true);
                    if (&page_directory[0] == &active_page_directory[0]) {
                        invalidate_page(get_address(dir_index, table_index));
                    }
                }
                self.map_virtual_page(get_page_address(table[table_index]));
                const page = @intToPtr([*]u8, self.virtual_page_address)
                    [page_offset..page_size];
                page_offset = 0;
                const copied = utils.memory_copy_truncate(page, data_left);
                data_left = data_left[copied..];
                table_index += 1;
            }
            dir_index += 1;
        }

        if (data_left.len > 0) {
            @panic("address_space_copy: data_left.len > 0 at end!");
        }
    }

    pub fn page_directory_memory_set(self: *Memory, page_directory: []u32,
            address: usize, byte: u8, len: usize) AllocError!void {
        const dir_index_start = get_directory_index(address);
        const table_index_start = get_table_index(address);
        var dir_index: usize = dir_index_start;
        var left = len;
        var page_offset = address % page_size;
        while (left > 0 and dir_index < tables_per_directory) {
            if (!table_is_present(page_directory[dir_index])) {
                try self.new_page_table(page_directory, dir_index, true);
            }
            var table_index: usize =
                if (dir_index == dir_index_start) table_index_start else 0;
            while (left > 0 and table_index < pages_per_table) {
                self.map_virtual_page(get_table_address(page_directory[dir_index]));
                const table = @intToPtr([*]u32, self.virtual_page_address);
                if (!page_is_present(table[table_index])) {
                    // TODO: Go through memory.Memory for pop_frame
                    const frame = try self.pop_frame();
                    self.map_virtual_page(get_table_address(page_directory[dir_index]));
                    set_entry(&table[table_index], frame, true);
                    if (&page_directory[0] == &active_page_directory[0]) {
                        invalidate_page(get_address(dir_index, table_index));
                    }
                }
                self.map_virtual_page(get_page_address(table[table_index]));
                var page = @intToPtr([*]u8, self.virtual_page_address)
                    [page_offset..page_size];
                if (page.len > left) {
                    page.len = left;
                }
                page_offset = 0;
                utils.memory_set(page, byte);
                left -= page.len;
                table_index += 1;
            }
            dir_index += 1;
        }
    }

    // TODO: This page structure iteration code is starting to seem very boiler
    // plate. Figure out a way to simplify it or else more likely make it
    // generic.

    // Assumes range address is page aligned.
    pub fn map_i(self: *Memory, page_directory: []u32, virtual_range: Range,
            physical_start: usize, user: bool) AllocError!void {
        const dir_index_start = get_directory_index(virtual_range.start);
        const table_index_start = get_table_index(virtual_range.start);
        var dir_index: usize = dir_index_start;
        var left = virtual_range.size;
        var physical_address = physical_start;
        while (left > 0 and dir_index < tables_per_directory) {
            if (!table_is_present(page_directory[dir_index])) {
                try self.new_page_table(page_directory, dir_index, user);
            }
            self.map_virtual_page(get_table_address(page_directory[dir_index]));
            const table = @intToPtr([*]u32, self.virtual_page_address);
            var table_index: usize =
                if (dir_index == dir_index_start) table_index_start else 0;
            while (left > 0 and table_index < pages_per_table) {
                const a = get_address(dir_index, table_index);
                set_entry(&table[table_index], physical_address, user);
                if (&page_directory[0] == &active_page_directory[0]) {
                    invalidate_page(a);
                }
                left -= page_size;
                physical_address += page_size;
                table_index += 1;
            }
            dir_index += 1;
        }

        if (left > 0) {
            @panic("map: left > 0 at end!");
        }
    }

    pub fn map(self: *Memory, virtual_range: Range, physical_start: usize,
            user: bool) AllocError!void {
        try self.map_i(active_page_directory[0..], virtual_range, physical_start, user);
    }
};
