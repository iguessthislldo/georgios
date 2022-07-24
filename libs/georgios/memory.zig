const std = @import("std");

const utils = @import("utils");

const syscalls = @import("system_calls.zig");

pub const AllocError = error {
    OutOfMemory,
    ZeroSizedAlloc,
};
pub const FreeError = error {
    InvalidFree,
};
pub const MemoryError = AllocError || FreeError;

pub const PageAllocator = struct {
    last_alloc_end: ?usize = null,

    fn alloc(self: *PageAllocator, n: usize, ptr_align: u29, len_align: u29, ra: usize) ![]u8 {
        _ = len_align;
        _ = ra;
        const page_size = 4096;
        const min_size = utils.align_up(n, 4096);
        const align_diff = ptr_align - @minimum(page_size, ptr_align);
        const area = syscalls.add_dynamic_memory(
            if (align_diff <= min_size - n) min_size else
                utils.align_up(min_size + align_diff, page_size))
            catch return std.mem.Allocator.Error.OutOfMemory;
        defer self.last_alloc_end = area.len;
        if (self.last_alloc_end) |last| {
            return area[last..];
        }
        return area[0..];
    }

    fn resize(self: *PageAllocator, buf: []u8, buf_align: u29, new_len: usize, len_align: u29,
            ret_addr: usize) ?usize {
        _ = self;
        _ = buf;
        _ = buf_align;
        _ = new_len;
        _ = len_align;
        _ = ret_addr;
        @panic("PageAllocator.resize called!");
    }

    fn free(self: *PageAllocator, buf: []u8, buf_align: u29, ret_addr: usize) void {
        _ = self;
        _ = buf;
        _ = buf_align;
        _ = ret_addr;
        // TODO
    }

    pub fn allocator(self: *PageAllocator) std.mem.Allocator {
        return std.mem.Allocator.init(self, alloc, resize, free);
    }
};
