// Based on http://bitsquid.blogspot.com/2015/08/allocation-adventures-3-buddy-allocator.html
//
// Also see prototype at scripts/prototypes/buddy.py

const memory = @import("memory.zig");
const Allocator = memory.Allocator;
const MemoryError = memory.MemoryError;
const util = @import("util.zig");

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
} || util.Error || MemoryError;

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

            pub fn initialize(self: *FreeBlocks, start: usize) void {
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

        pub fn initialize(self: *Self, start: usize) void {
            self.allocator = Allocator{
                .alloc_impl = alloc,
                .free_impl = free,
            };
            self.start = start;
            self.free_blocks.initialize(start);
            self.block_statuses.reset();
            self.block_statuses.set(0, .Free) catch unreachable;
        }

        fn level_block_count(level: usize) usize {
            return (usize(1) << @truncate(util.UsizeLog2Type, level)) - 1;
        }

        fn level_to_block_size(level: usize) usize {
            return max_size >> @truncate(util.UsizeLog2Type, level);
        }

        fn block_size_to_level(size: usize) usize {
            return level_count - util.int_log2(usize, size / min_size) - 1;
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

        pub fn alloc(allocator: *Allocator, size: usize) MemoryError!usize {
            const self = @fieldParentPtr(Self, "allocator", allocator);

            if (size > max_size) {
                return MemoryError.OutOfMemory;
            }

            const target_size = util.pow2_round_up(usize, size);
            const target_level = block_size_to_level(target_size);

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
                    return MemoryError.OutOfMemory;
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

            return @ptrToInt(address);
        }

        fn merge(self: *Self, level: usize, index: usize) Error!void {
            if (level == 0) {
                return Error.OutOfBounds;
            }

            const buddy_index = get_buddy_index(index);
            const new_level = level - 1;
            const new_index = index << 1;

            // Assert existing blocks are free and new/parrent block is split
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

        fn free(allocator: *Allocator, address: usize) MemoryError!void {
            const self = @fieldParentPtr(Self, "allocator", allocator);
            const block = @intToPtr(FreeBlock.Ptr, address);

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
                return MemoryError.InvalidPointerArgument;
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

test "BuddyAllocator" {
    const std = @import("std");

    const ptr_size = util.int_bit_size(usize);
    const free_pointer_size: usize = switch (ptr_size) {
        32 => usize(8),
        64 => usize(16),
        else => unreachable,
    };
    std.testing.expectEqual(free_pointer_size, @sizeOf(?FreeBlock.Ptr));
    std.testing.expectEqual(free_pointer_size * 2, min_size);

    const size: usize = 128;
    const ABuddyAllocator = BuddyAllocator(size);
    const expected_level_count: usize = switch (ptr_size) {
        32 => usize(4),
        64 => usize(3),
        else => unreachable,
    };
    std.testing.expectEqual(
        expected_level_count, ABuddyAllocator.level_count);

    var b = ABuddyAllocator{};
    var m: [size]u8 = undefined;
    b.initialize(@ptrToInt(&m));
    const a = &b.allocator;
    {
        const s = 32;
        const p = try a.alloc([s]u8);
        @memset(p, 0x01, s);
    }
    {
        const s = 32;
        const p = try a.alloc([s]u8);
        @memset(p, 0x04, s);
    }
    {
        const s = 64;
        const p = try a.alloc([s]u8);
        @memset(p, 0xff, s);
        const expected =
            "\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01" ++
            "\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01" ++
            "\x04\x04\x04\x04\x04\x04\x04\x04\x04\x04\x04\x04\x04\x04\x04\x04" ++
            "\x04\x04\x04\x04\x04\x04\x04\x04\x04\x04\x04\x04\x04\x04\x04\x04" ++
            "\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff" ++
            "\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff" ++
            "\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff" ++
            "\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff";
        std.testing.expectEqualSlices(u8, expected[0..], m[0..]);
        try a.free([s]u8, p);
    }
    {
        const s = 32;
        const p = try a.alloc([s]u8);
        @memset(p, 0x88, s);
    }
    {
        const s = 32;
        const p = try a.alloc([s]u8);
        @memset(p, 0x77, s);
    }
    const expected_final =
        "\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01" ++
        "\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01" ++
        "\x04\x04\x04\x04\x04\x04\x04\x04\x04\x04\x04\x04\x04\x04\x04\x04" ++
        "\x04\x04\x04\x04\x04\x04\x04\x04\x04\x04\x04\x04\x04\x04\x04\x04" ++
        "\x88\x88\x88\x88\x88\x88\x88\x88\x88\x88\x88\x88\x88\x88\x88\x88" ++
        "\x88\x88\x88\x88\x88\x88\x88\x88\x88\x88\x88\x88\x88\x88\x88\x88" ++
        "\x77\x77\x77\x77\x77\x77\x77\x77\x77\x77\x77\x77\x77\x77\x77\x77" ++
        "\x77\x77\x77\x77\x77\x77\x77\x77\x77\x77\x77\x77\x77\x77\x77\x77";
    std.testing.expectEqualSlices(u8, expected_final[0..], m[0..]);
}
