// x86 Memory Management
//
// Memory management consistents of frame management and page management.
// Frames are chunks of real/physical memory that are joined in a
// linked list when unused:
//
//                  +-----+  +-----+
// next_free_frame->|Frame|->|Frame|->...->null
//                  +-----+  +-----+
//
// Pages are the in-use frames that mapped into the virtual memory that the
// kernel and programs can directly access. They are accessed by the CPU using
// a set of strutures the kernel has to set up:
//
//        Page Directory   Page Tables  Used Frames
//       +-------------+  +------+     +----------------+
// %cr3->|Table 0 Ptr. |->|Page 0|---->|Frame for Page 0|
//       +-------------+  +------+     +----------------+
//       |Table 1 Ptr. |  |Page 1|---->|Frame for Page 0|
//       +-------------+  +------+     +----------------+
//       |...          |  |...   |     |...             |
//       +-------------+  +------+     +----------------+
//
// NOTE: In Georgios %cr3 is always set to the active_page_directory array.
// With the exception of kernel space, whole new virtual memory layouts are
// copied to and from active_page_directory to swap memory, followed by a call
// to reload_active_page_directory to inform the CPU the page directory
// changed.
//
// For Reference See:
//   https://wiki.osdev.org/Paging
//   https://ethv.net/workshops/osdev/notes/notes-2.html

const std = @import("std");
const sliceAsBytes = std.mem.sliceAsBytes;

const georgios = @import("georgios");
const utils = @import("utils");

const kernel = @import("root").kernel;
const memory = kernel.memory;
const RealMemoryMap = memory.RealMemoryMap;
const AllocError = memory.AllocError;
const FreeError = memory.FreeError;
const Range = memory.Range;
const print = kernel.print;
const BuddyAllocator = @import("../buddy_allocator.zig").BuddyAllocator;

const platform = @import("platform.zig");

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
extern var _VIRTUAL_LOW_START: u32;

pub fn get_address(dir_index: usize, table_index: usize) callconv(.Inline) usize {
    return dir_index * table_pages_size + table_index * page_size;
}

// Page Directory Operations
pub fn get_directory_index(address: u32) callconv(.Inline) u32 {
    return (address & 0xffc00000) >> 22;
}

extern var _VIRTUAL_OFFSET: u32;
pub fn get_kernel_space_start_directory_index() callconv(.Inline) u32 {
    return get_directory_index(@ptrToInt(&_VIRTUAL_OFFSET));
}

pub fn table_is_present(entry: u32) callconv(.Inline) bool {
    return (entry & 1) == 1;
}

pub fn get_table_address(entry: u32) callconv(.Inline) u32 {
    return entry & 0xfffff000;
}
// (End of Page Directory Operations)

// Page Table Operations
pub fn get_table_index(address: u32) callconv(.Inline) u32 {
    return (address & 0x003ff000) >> 12;
}

pub fn page_is_present(entry: u32) callconv(.Inline) bool {
    // Bit 9 (0x200) marks a guard page to Georgios. This will be marked as not
    // present in the entry itself (bit 1) so that it causes a page fault if
    // accessed.
    return (entry & 0x201) != 0;
}

pub fn as_guard_page(entry: u32) callconv(.Inline) u32 {
    return (entry & 0xfffffffe) | 0x200;
}

pub fn page_is_guard_page(entry: u32) callconv(.Inline) bool {
    return (entry & 0x201) == 0x200;
}

pub fn get_page_address(entry: u32) callconv(.Inline) u32 {
    return entry & 0xfffff000;
}

pub fn present_entry(address: u32) callconv(.Inline) u32 {
    return (address & 0xfffff000) | 1;
}

pub fn set_entry(entry: *allowzero u32, address: usize, user: bool) callconv(.Inline) void {
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

const FrameAccessSlot = struct {
    i: u16,
    current_frame_address: ?u32 = null,
    page_address: u32 = undefined,
    page_table_entry: *u32 = undefined,

    pub fn init(self: *FrameAccessSlot) void {
        self.page_address = @ptrToInt(&_VIRTUAL_LOW_START) + page_size * self.i;
        self.page_table_entry = &kernel_page_tables[get_table_index(self.page_address)];
    }
};

/// Before we can allocate memory properly we need to be able to manually
/// change physical memory to setup frame allocation and create new page
/// tables. We can bootstrap this process by using a bit of real and virtual
/// memory we know is safe to use and map it to the frame want to change.
///
/// This involves reserving a FrameAccessSlot using a FrameAccess object for
/// the type to map. There can only be one FrameAccess using a slot at a time
/// or else there will be a panic. See below for the slot objects.
fn FrameAccess(comptime Type: type) type {
    const Traits = @typeInfo(Type);
    comptime var slice_len: ?comptime_int = null;
    comptime var PtrType: type = undefined;
    const GetType = switch (Traits) {
        std.builtin.TypeId.Array => |array_type| blk: {
            slice_len = array_type.len;
            PtrType = [*]array_type.child;
            break :blk []array_type.child;
        },
        else => else_blk: {
            PtrType = *Type;
            break :else_blk *Type;
        }
    };

    return struct {
        const Self = @This();

        slot: *FrameAccessSlot,
        ptr: PtrType,

        pub fn new(slot: *FrameAccessSlot, frame_address: u32) Self {
            if (slot.current_frame_address != null) {
                @panic("The FrameAccess slot is already active!");
            }
            slot.current_frame_address = frame_address;

            const needed_entry = (frame_address & 0xfffff000) | 1;
            if (slot.page_table_entry.* != needed_entry) {
                slot.page_table_entry.* = needed_entry;
                invalidate_page(slot.page_address);
            }

            return Self{.slot = slot, .ptr = @intToPtr(PtrType, slot.page_address)};
        }

        pub fn get(self: *const Self) GetType {
            return if (slice_len) |l| self.ptr[0..l] else self.ptr;
        }

        pub fn done(self: *const Self) void {
            if (self.slot.current_frame_address == null) {
                @panic("Done called, but slot is already inactive");
            }
            self.slot.current_frame_address = null;
        }
    };
}

var pmem_frame_access_slot: FrameAccessSlot = .{.i = 0};
var page_table_frame_access_slot: FrameAccessSlot = .{.i = 1};
var page_frame_access_slot: FrameAccessSlot = .{.i = 2};
// NOTE: More cannot be added unless room is made in the linking script by
// adjusting .low_force_space_begin_align to make _REAL_LOW_END increase.

/// Add Frame Groups to Our Memory Map from Multiboot Memory Map
pub fn process_multiboot2_mmap(map: *RealMemoryMap, tag: *const Range) void {
    const entry_size = @intToPtr(*u32, tag.start + 8).*;
    const entries_end = tag.start + tag.size;
    var entry_ptr = tag.start + 16;
    while (entry_ptr < entries_end) : (entry_ptr += entry_size) {
        if (@intToPtr(*u32, entry_ptr + 16).* == 1) {
            var range_start = @intCast(usize, @intToPtr(*u64, entry_ptr).*);
            var range_size = @intCast(usize, @intToPtr(*u64, entry_ptr + 8).*);
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

pub const ManagerImpl = struct {
    const FreeFramePtr = ?usize;
    const FreeFramePtrAccess = FrameAccess(FreeFramePtr);
    fn access_free_frame(frame: u32) FreeFramePtrAccess {
        return FreeFramePtrAccess.new(&pmem_frame_access_slot, frame);
    }

    const TableAccess = FrameAccess([pages_per_table]u32);
    fn access_page_table(frame: u32) TableAccess {
        return TableAccess.new(&page_table_frame_access_slot, frame);
    }

    const PageAccess = FrameAccess([page_size]u8);
    fn access_page(frame: u32) PageAccess {
        return PageAccess.new(&page_frame_access_slot, frame);
    }

    const kernel_space_size = utils.Gi(1);
    const kernel_space_start = 0xc0000000;
    const kernel_space = @intToPtr([*]u8, kernel_space_start)[0..kernel_space_size];
    const KernelSpacePageAlloc = BuddyAllocator(kernel_space_size, page_size, .InSelf);

    parent: *memory.Manager = undefined,
    next_free_frame: FreeFramePtr = null,
    kernel_tables_index_start: usize = 0,
    start_of_virtual_space: usize = 0,
    kernel_space_page_alloc: KernelSpacePageAlloc = undefined,
    page_allocator: memory.Allocator = undefined,

    pub fn init(self: *ManagerImpl, parent: *memory.Manager, memory_map: *RealMemoryMap) void {
        self.parent = parent;
        self.page_allocator.alloc_impl = ManagerImpl.page_alloc;
        self.page_allocator.free_impl = ManagerImpl.page_free;
        parent.big_alloc = &self.page_allocator;
        pmem_frame_access_slot.init();
        page_table_frame_access_slot.init();
        page_frame_access_slot.init();

        for (memory_map.frame_groups[0..memory_map.frame_group_count]) |*i| {
            parent.total_frame_count += i.frame_count;
            var frame: usize = 0;
            while (frame < i.frame_count) {
                self.push_frame(i.start + frame * frame_size);
                frame += 1;
            }
        }
        parent.free_frame_count = parent.total_frame_count;

        // var counted: usize = 0;
        // while (true) {
        //     _ = self.pop_frame() catch break;
        //     counted += 1;
        // }
        // print.format("total_count: {}, counted: {}\n", total_count, counted);

        self.start_of_virtual_space = utils.align_up(
            @ptrToInt(kernel_page_tables.ptr) + kernel_page_tables.len * table_size,
            table_pages_size);
        self.kernel_space_page_alloc.init(kernel_space) catch
            @panic("failed to init kernel page allocator");
        const range = kernel_space[0..self.start_of_virtual_space - kernel_space_start];
        self.kernel_space_page_alloc.reserve(range) catch
            @panic("failed to reserve space in kernel page allocator");
    }

    pub fn push_frame(self: *ManagerImpl, frame: usize) void {
        // Put the current next_free_frame into the frame.
        const access = access_free_frame(frame);
        access.get().* = self.next_free_frame;
        access.done();
        // Point to that frame.
        self.next_free_frame = frame;
        self.parent.free_frame_count += 1;
    }

    pub fn pop_frame(self: *ManagerImpl) AllocError!usize {
        if (self.next_free_frame) |frame| {
            const prev = frame;
            // Get the "next" next_free_frame from the contents of the current
            // one.
            const access = access_free_frame(frame);
            self.next_free_frame = access.get().*;
            access.done();
            self.parent.free_frame_count -= 1;
            // Return the previous next_free_frame
            return prev;
        }
        return AllocError.OutOfMemory;
    }

    const PageIter = struct {
        mgr: *ManagerImpl,
        page_directory: []u32,
        virtual_range: Range,
        offset: usize,
        user: bool,
        dir_index: usize,
        table_index: usize,
        left: usize,
        initial_call: bool = true,
        changed_table: bool = undefined,

        fn new(mgr: *ManagerImpl, page_directory: []u32,
                virtual_range: Range, align_to_page_size: bool, user: bool) PageIter {
            return .{
                .mgr = mgr,
                .page_directory = page_directory,
                .virtual_range = virtual_range,
                .offset = virtual_range.start % page_size,
                .user = user,
                .dir_index = get_directory_index(virtual_range.start),
                .table_index = get_table_index(virtual_range.start),
                .left = if (align_to_page_size) utils.align_up(virtual_range.size, page_size)
                    else virtual_range.size,
            };
        }

        fn address(self: *PageIter) usize {
            return get_address(self.dir_index, self.table_index);
        }

        fn iter(self: *PageIter) ?*PageIter {
            if (self.left == 0 or self.dir_index >= tables_per_directory) return null;
            if (self.initial_call) {
                self.initial_call = false;
                self.changed_table = true;
            } else {
                self.left -= @minimum(page_size, self.left);
                self.table_index += 1;
                self.offset = 0;
                self.changed_table = self.table_index >= pages_per_table;
                if (self.changed_table) {
                    self.table_index = 0;
                    self.dir_index += 1;
                }
                if (self.left == 0 or self.dir_index >= tables_per_directory) return null;
            }

            return self;
        }

        fn no_table(self: *PageIter) bool {
            return !table_is_present(self.page_directory[self.dir_index]);
        }

        fn ensure_table(self: *PageIter) AllocError!void {
            if (self.changed_table and self.no_table()) {
                try self.mgr.new_page_table(self.page_directory, self.dir_index, self.user);
            }
        }

        fn get_table_access(self: *PageIter) TableAccess {
            return access_page_table(get_table_address(self.page_directory[self.dir_index]));
        }

        fn map_to_i(self: *PageIter, table_entry: *u32, physical_address: usize) void {
            set_entry(table_entry, physical_address, self.user);
            if (&self.page_directory[0] == &active_page_directory[0]) {
                invalidate_page(self.address());
            }
        }

        fn ensure_page(self: *PageIter) AllocError!void {
            try self.ensure_table();

            const table_access = self.get_table_access();
            defer table_access.done();
            const table = table_access.get();

            if (page_is_guard_page(table[self.table_index])) {
                @panic("ensure_page: page is guard page!");
            }

            const table_entry = &table[self.table_index];
            if (!page_is_present(table_entry.*)) {
                self.map_to_i(table_entry, try self.mgr.pop_frame());
            }
        }

        fn map_to(self: *PageIter, physical_address: usize) AllocError!void {
            try self.ensure_table();

            const table_access = self.get_table_access();
            defer table_access.done();
            const table = table_access.get();

            if (page_is_guard_page(table[self.table_index])) {
                @panic("map_to: page is guard page!");
            }

            if (page_is_present(table[self.table_index])) {
                @panic("map_to: page already present!");
            }

            self.map_to_i(&table[self.table_index], physical_address);
        }

        fn access(self: *PageIter) PageAccess {
            const table_access = self.get_table_access();
            defer table_access.done();
            const table = table_access.get();
            return access_page(get_page_address(table[self.table_index]));
        }
    };

    // TODO: Read/Write and Any Other Options
    pub fn mark_virtual_memory_present(self: *ManagerImpl,
            page_directory: []u32, range: Range, user: bool) AllocError!void {
        var page_iter = PageIter.new(self, page_directory, range, true, user);
        while (page_iter.iter()) |page| {
            try page.map_to(try self.pop_frame());
        }
    }

    // TODO
    fn mark_virtual_memory_absent(self: *ManagerImpl, range: Range) void {
        _ = self;
        _ = range;
    }

    pub fn map(self: *ManagerImpl, virtual_range: Range, physical_start: usize,
            user: bool) AllocError!void {
        var page_iter = PageIter.new(self, active_page_directory[0..], virtual_range, true, user);
        var physical_address = physical_start;
        while (page_iter.iter()) |page| {
            try page.map_to(physical_address);
            physical_address +%= page_size;
        }
    }

    pub fn page_directory_memory_dump(self: *ManagerImpl, page_directory: []u32,
            address: usize, len: usize) void {
        const range = Range{.start = address, .size = len};
        var page_iter = PageIter.new(self, page_directory, range, false, true);
        while (page_iter.iter()) |page| {
            const access = page.access();
            defer access.done();
            const page_data = access.get()[page.offset..];
            try georgios.get_console_writer().print("{}", .{utils.fmt_dump_hex(page_data)});
        }
    }

    pub fn page_directory_memory_copy(self: *ManagerImpl, page_directory: []u32,
            address: usize, data: []const u8) AllocError!void {
        // print.format("page_directory_memory_copy: {} b to {:a}\n", .{data.len, address});
        const range = Range{.start = address, .size = data.len};
        var page_iter = PageIter.new(self, page_directory, range, false, true);
        var data_left = data;
        while (page_iter.iter()) |page| {
            try page.ensure_page();
            const access = page.access();
            defer access.done();
            const copy_to = access.get()[page.offset..];
            const copied = utils.memory_copy_truncate(copy_to, data_left);
            data_left = data_left[copied..];
        }

        if (data_left.len > 0) {
            @panic("page_directory_memory_copy: data_left.len > 0");
        }
    }

    pub fn page_directory_memory_set(self: *ManagerImpl, page_directory: []u32,
            address: usize, byte: u8, len: usize) AllocError!void {
        // print.format("page_directory_memory_set: {} b at {:a}\n", .{len, address});
        const range = Range{.start = address, .size = len};
        var page_iter = PageIter.new(self, page_directory, range, false, true);
        while (page_iter.iter()) |page| {
            try page.ensure_page();
            const access = page.access();
            defer access.done();
            utils.memory_set(access.get()[page.offset..], byte);
        }
    }

    pub fn get_unused_kernel_space(self: *ManagerImpl, requested_size: usize) AllocError!Range {
        return Range.from_bytes(
            try self.kernel_space_page_alloc.allocator.alloc_array(u8, requested_size));
    }

    pub fn new_page_table(self: *ManagerImpl, page_directory: []u32,
            dir_index: usize, user: bool) AllocError!void {
        // print.format("new_page_table {:x}\n", dir_index);
        // TODO: Go through memory.Memory
        const table_address = try self.pop_frame();
        // TODO set_entry for page_directory
        set_entry(&page_directory[dir_index], table_address, user);
        const access = access_page_table(table_address);
        const table = access.get();
        var i: usize = 0;
        while (i < pages_per_table) {
            table[i] = 0;
            i += 1;
        }
        access.done();
    }

    pub fn make_guard_page(self: *ManagerImpl, page_directory: ?[]u32,
            address: usize, user: bool) AllocError!void {
        const page_dir = page_directory orelse active_page_directory[0..];
        const dir_index = get_directory_index(address);
        if (!table_is_present(page_dir[dir_index])) {
            try self.new_page_table(page_dir, dir_index, user);
        }
        const access = access_page_table(get_table_address(page_dir[dir_index]));
        defer access.done();
        const table = access.get();
        const table_index = get_table_index(address);
        const free_frame: ?u32 = if (page_is_present(table[table_index]))
            get_page_address(table[table_index]) else null;
        table[table_index] = as_guard_page(table[table_index]);
        if (&page_dir[0] == &active_page_directory[0]) {
            invalidate_page(get_address(dir_index, table_index));
        }
        if (free_frame) |addr| {
            self.push_frame(addr);
        }
    }

    fn page_alloc(allocator: *memory.Allocator, size: usize, align_to: usize) AllocError![]u8 {
        _ = align_to;
        const self = @fieldParentPtr(ManagerImpl, "page_allocator", allocator);
        const range = try self.get_unused_kernel_space(size);
        try self.mark_virtual_memory_present(active_page_directory[0..], range, false);
        return range.to_slice(u8);
    }

    fn page_free(allocator: *memory.Allocator, value: []const u8, aligned_to: usize) FreeError!void {
        const self = @fieldParentPtr(ManagerImpl, "page_allocator", allocator);
        // TODO
        _ = self;
        _ = value;
        _ = aligned_to;
    }

    pub fn new_page_directory(self: *ManagerImpl) AllocError![]u32 {
        _ = self;
        const page_directory =
            try self.parent.big_alloc.alloc_array(u32, tables_per_directory);
        _ = utils.memory_set(sliceAsBytes(page_directory[0..]), 0);
        return page_directory;
    }
};
