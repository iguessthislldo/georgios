// Buddy System Allocation Implementation
//
// Based on http://bitsquid.blogspot.com/2015/08/allocation-adventures-3-buddy-allocator.html
//
// Also see prototype at scripts/prototypes/buddy.py
//
// For Reference See:
//   https://en.wikipedia.org/wiki/Buddy_memory_allocation
//
// TODO: Make Resizable
// TODO: Space optimize allocations that are smaller then FreeBlock, maybe by
// lumping them together in shared blocks?

const memory = @import("memory.zig");
const Allocator = memory.Allocator;
const MemoryError = memory.MemoryError;
const AllocError = memory.AllocError;
const FreeError = memory.FreeError;
const util = @import("utils");
const print = @import("print.zig");

const BlockStatus = packed enum(u2) {
    Invalid = 0,
    Split,
    Free,
    Used,
};

const Error = error {
    WrongBlockStatus,
    InternalError,
    RequestedSizeTooSmall,
    RequestedSizeTooLarge,
} || util.Error;

const FreeBlock = struct {
    const ConstPtr = *allowzero const FreeBlock;
    const Ptr = *allowzero FreeBlock;
    prev: ?Ptr,
    next: ?Ptr,
};
const min_size: usize = @sizeOf(FreeBlock);

pub fn BuddyAllocator(max_size_arg: usize) type {
    return struct {
        const Self = @This();

        pub const max_size: usize = max_size_arg;

        const max_level_block_count = max_size / min_size;
        const level_count: usize = util.int_log2(usize, max_level_block_count) + 1;
        const unique_block_count: usize = level_block_count(level_count);

        const FreeBlocks = struct {
            lists: [level_count]?FreeBlock.Ptr = undefined,

            pub fn init(self: *FreeBlocks, start: usize) void {
                for (self.lists) |*ptr| {
                    ptr.* = null;
                }
                self.push(0, @intToPtr(FreeBlock.Ptr, start)) catch unreachable;
            }

            pub fn get(self: *FreeBlocks, level: usize) Error!?FreeBlock.Ptr {
                if (level >= level_count) {
                    return Error.OutOfBounds;
                }
                return self.lists[level];
            }

            pub fn push(self: *FreeBlocks, level: usize,
                    block: FreeBlock.Ptr) Error!void {
                if (level >= level_count) {
                    return Error.OutOfBounds;
                }
                const current_maybe = self.lists[level];
                if (current_maybe) |current| {
                    current.prev = block;
                }
                block.next = current_maybe;
                block.prev = null;
                self.lists[level] = block;
            }

            // TODO: Unused, is it even needed?
            pub fn pop(self: *FreeBlocks, level: usize) Error!?FreeBlock.Ptr {
                if (level >= level_count) {
                    return Error.OutOfBounds;
                }
                const current_maybe = self.lists[level];
                if (current_maybe) |current| {
                    self.lists[level] = current.next;
                    if (current.next) |next| {
                        next.prev = null;
                    }
                }
                return current_maybe;
            }

            pub fn remove_block(self: *FreeBlocks, level: usize,
                    block: FreeBlock.ConstPtr) void {
                if (block.prev) |prev| {
                    prev.next = block.next;
                } else {
                    self.lists[level] = block.next;
                }
                if (block.next) |next| {
                    next.prev = block.prev;
                }
            }
        };

        allocator: Allocator = undefined,
        start: usize = undefined,
        free_blocks: FreeBlocks = undefined,
        block_statuses: util.PackedArray(
            BlockStatus, unique_block_count) = undefined,

        pub fn init(self: *Self, start: usize) void {
            self.allocator = Allocator{
                .alloc_impl = alloc,
                .free_impl = free,
            };
            self.start = start;
            self.free_blocks.init(start);
            self.block_statuses.reset();
            self.block_statuses.set(0, .Free) catch unreachable;
        }

        fn level_block_count(level: usize) usize {
            return (@as(usize, 1) << @truncate(util.UsizeLog2Type, level)) - 1;
        }

        fn level_to_block_size(level: usize) usize {
            return max_size >> @truncate(util.UsizeLog2Type, level);
        }

        fn size_to_level(size: usize) usize {
            const target_size = util.max(usize, min_size, util.pow2_round_up(usize, size));
            return level_count - util.int_log2(usize, target_size / min_size) - 1;
        }

        fn unique_id(level: usize, index: usize) usize {
            return level_block_count(level) + index;
        }

        fn get_index(self: *const Self, level: usize,
                address: FreeBlock.ConstPtr) usize {
            return (@ptrToInt(address) - self.start) / level_to_block_size(level);
        }

        fn get_pointer(self: *const Self, level: usize,
                index: usize) FreeBlock.Ptr {
            return @intToPtr(FreeBlock.Ptr,
                self.start + index * level_to_block_size(level));
        }

        fn get_buddy_index(index: usize) usize {
            return if ((index % 2) == 1) (index - 1) else (index + 1);
        }

        fn assert_unique_id(self: *Self, level: usize, index: usize,
                expected_status: BlockStatus) Error!usize {
            const id = unique_id(level, index);
            const status = try self.block_statuses.get(id);
            if (status != expected_status) {
                return Error.WrongBlockStatus;
            }
            return id;
        }

        fn split(self: *Self, level: usize, index: usize) Error!void {
            const this_unique_id = try self.assert_unique_id(
                level, index, .Free);

            const this_ptr = self.get_pointer(level, index);
            const new_level: usize = level + 1;
            const new_index = index << 1;
            const buddy_index = new_index + 1;
            const buddy_ptr = self.get_pointer(new_level, buddy_index);

            // Update Free Blocks
            self.free_blocks.remove_block(level, this_ptr);
            try self.free_blocks.push(new_level, buddy_ptr);
            try self.free_blocks.push(new_level, this_ptr);

            // Update Statuses
            try self.block_statuses.set(this_unique_id, BlockStatus.Split);
            try self.block_statuses.set(
                unique_id(new_level, new_index), BlockStatus.Free);
            try self.block_statuses.set(
                unique_id(new_level, buddy_index), BlockStatus.Free);
        }

        pub fn alloc(allocator: *Allocator, size: usize) AllocError![]u8 {
            const self = @fieldParentPtr(Self, "allocator", allocator);

            if (size > max_size) {
                return AllocError.OutOfMemory;
            }

            const target_level = size_to_level(size);

            // Figure out how many (if any) levels we need to split a block in
            // to get a free block in our target level.
            var address_maybe: ?FreeBlock.Ptr = null;
            var level = target_level;
            while (true) {
                address_maybe = self.free_blocks.get(level) catch unreachable;
                if (address_maybe != null) {
                    break;
                }
                if (level == 0) {
                    return AllocError.OutOfMemory;
                }
                level -= 1;
            }

            // If we need to split blocks, do that
            var split_level = level;
            while (split_level != target_level) {
                self.split(split_level,
                    self.get_index(split_level, address_maybe.?))
                    catch unreachable;
                split_level += 1;
                address_maybe = self.free_blocks.get(split_level) catch unreachable;
                if (address_maybe == null) {
                    unreachable;
                }
            }

            // Reserve it
            const address = address_maybe.?;
            self.free_blocks.remove_block(target_level, address);
            const index = self.get_index(target_level, address);
            const id = unique_id(target_level, index);
            self.block_statuses.set(id, .Used) catch unreachable;

            return @ptrCast([*]u8, address)[0..size];
        }

        fn merge(self: *Self, level: usize, index: usize) Error!void {
            if (level == 0) {
                return Error.OutOfBounds;
            }

            const buddy_index = get_buddy_index(index);
            const new_level = level - 1;
            const new_index = index >> 1;

            // Assert existing blocks are free and new/parent block is split
            const this_unique_id = try self.assert_unique_id(level, index, .Free);
            const buddy_unique_id = try self.assert_unique_id(level, buddy_index, .Free);
            const new_unique_id = try self.assert_unique_id(new_level, new_index, .Split);

            // Remove pointers to the old blocks
            const this_ptr = self.get_pointer(level, index);
            const buddy_ptr = self.get_pointer(level, buddy_index);
            self.free_blocks.remove_block(level, this_ptr);
            self.free_blocks.remove_block(level, buddy_ptr);

            // Push New Block into List
            try self.free_blocks.push(new_level, self.get_pointer(new_level, new_index));

            // Set New Statuses
            try self.block_statuses.set(this_unique_id, .Invalid);
            try self.block_statuses.set(buddy_unique_id, .Invalid);
            try self.block_statuses.set(new_unique_id, .Free);
        }

        fn free(allocator: *Allocator, value: []const u8) FreeError!void {
            const self = @fieldParentPtr(Self, "allocator", allocator);

            if (value.len > max_size) return FreeError.InvalidFree;

            const address = @ptrToInt(value.ptr);
            const block = @intToPtr(FreeBlock.Ptr, address);
            if (value.len > 0) {
                const level = size_to_level(value.len);
                const index = self.get_index(level, block);
                const id = unique_id(level, index);
                const status = self.block_statuses.get(id) catch unreachable;
                if (status != .Used) {
                    print.format(
                        "Error: BuddyAllocator.free will return InvalidFree for {:a} " ++
                        "size {} because its block at level {} index {} has status {}\n",
                        .{address, value.len, level, index, status});
                }
            }
            // else if it's zero-sized then it probably came from something like C
            // free where we don't get the size.

            // Find the level
            var level = level_count - 1;
            var id_maybe: ?usize = null;
            var index: usize = undefined;
            while (id_maybe == null) {
                index = self.get_index(level, block);
                if (self.assert_unique_id(level, index, .Used)) |i| {
                    id_maybe = i;
                } else |e| switch (e) {
                    Error.WrongBlockStatus => {
                        if (level == 0) {
                            break;
                        }
                        level -= 1;
                    },
                    else => unreachable,
                }
            }
            if (id_maybe == null) {
                return FreeError.InvalidFree;
            }
            const id = id_maybe.?;

            // Insert Block into List and Mark as Free
            self.free_blocks.push(level, block) catch unreachable;
            self.block_statuses.set(id, .Free) catch unreachable;

            // Merge Until Buddy isn't Free or Level Is 0
            while (level > 0) {
                const buddy_index = get_buddy_index(index);
                const buddy_unique_id = unique_id(level, buddy_index);
                const buddy_status = self.block_statuses.get(buddy_unique_id)
                    catch unreachable;
                if (buddy_status == .Free) {
                    self.merge(level, index) catch unreachable;
                    index >>= 1;
                } else {
                    break;
                }
                level -= 1;
            }
        }
    };
}

const List = @import("list.zig").List;
const AllocList = List([]u8);
fn test_helper(
        a: *Allocator, al: *AllocList, size: usize, fill: u8) MemoryError!void {
    const s = try a.alloc_array(u8, size);
    for (s) |*e| e.* = fill;
    try al.push_front(s);
}
test "BuddyAllocator" {
    const std = @import("std");

    const ptr_size = util.int_bit_size(usize);
    const free_pointer_size: usize = switch (ptr_size) {
        32 => @as(usize, 8),
        64 => @as(usize, 16),
        else => unreachable,
    };
    std.testing.expectEqual(free_pointer_size, @sizeOf(?FreeBlock.Ptr));
    std.testing.expectEqual(free_pointer_size * 2, min_size);

    const size: usize = 128;
    const ABuddyAllocator = BuddyAllocator(size);
    const expected_level_count: usize = switch (ptr_size) {
        32 => @as(usize, 4),
        64 => @as(usize, 3),
        else => unreachable,
    };
    std.testing.expectEqual(
        expected_level_count, ABuddyAllocator.level_count);

    var b = ABuddyAllocator{};
    var m: [size]u8 = undefined;
    b.init(@ptrToInt(&m));
    const a = &b.allocator;

    var al_alloc = memory.UnitTestAllocator{};
    al_alloc.init();
    defer al_alloc.done();
    var al = AllocList{.alloc = &al_alloc.allocator};

    try test_helper(a, &al, @as(usize, 32), @as(u8, 0x01));
    try test_helper(a, &al, @as(usize, 32), @as(u8, 0x04));
    try test_helper(a, &al, @as(usize, 64), @as(u8, 0xff));
    std.testing.expectEqualSlices(u8,
        "\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01" ++
        "\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01" ++
        "\x04\x04\x04\x04\x04\x04\x04\x04\x04\x04\x04\x04\x04\x04\x04\x04" ++
        "\x04\x04\x04\x04\x04\x04\x04\x04\x04\x04\x04\x04\x04\x04\x04\x04" ++
        "\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff" ++
        "\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff" ++
        "\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff" ++
        "\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff",
        m[0..]);
    try a.free_array((try al.pop_front()).?);

    const byte: u8 = 0xaa;
    try test_helper(a, &al, @as(usize, 1), byte);
    std.testing.expectEqual(byte, m[32 * 2]);
    try a.free_array((try al.pop_front()).?);

    try test_helper(a, &al, @as(usize, 32), @as(u8, 0x88));
    try test_helper(a, &al, @as(usize, 32), @as(u8, 0x77));
    std.testing.expectEqualSlices(u8,
        "\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01" ++
        "\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01" ++
        "\x04\x04\x04\x04\x04\x04\x04\x04\x04\x04\x04\x04\x04\x04\x04\x04" ++
        "\x04\x04\x04\x04\x04\x04\x04\x04\x04\x04\x04\x04\x04\x04\x04\x04" ++
        "\x88\x88\x88\x88\x88\x88\x88\x88\x88\x88\x88\x88\x88\x88\x88\x88" ++
        "\x88\x88\x88\x88\x88\x88\x88\x88\x88\x88\x88\x88\x88\x88\x88\x88" ++
        "\x77\x77\x77\x77\x77\x77\x77\x77\x77\x77\x77\x77\x77\x77\x77\x77" ++
        "\x77\x77\x77\x77\x77\x77\x77\x77\x77\x77\x77\x77\x77\x77\x77\x77",
        m[0..]);
    while (try al.pop_front()) |slice| {
        try a.free_array(slice);
    }
}
