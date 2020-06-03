// Based on http://bitsquid.blogspot.com/2015/08/allocation-adventures-3-buddy-allocator.html
//
// Also see prototype at scripts/prototypes/buddy.py

const util = @import("util.zig");

const BlockStatus = packed enum(u2) {
    invalid,
    split,
    free,
    used,
};

const Error = error {
    OutOfMemory,
    WrongBlockStatus,
    InternalError,
    InvalidPointer,
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
        const UsizeShift = util.IntLog2Type(usize);
        const unique_block_count: usize = (1 << @truncate(UsizeShift, level_count)) - 1;

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

            pub fn pop(self: *FreeBlocks, level: usize) Error!?FreeBlock.Ptr {
                if (level >= level_count) {
                    return Error.OutOfBounds;
                }
                const current_maybe = self.lists[level];
                if (current_maybe) |current| {
                    self.lists[level] = current.next;
                    if (cerrent.next) |next| {
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

        start: usize = undefined,
        free_blocks: FreeBlocks = undefined,
        block_statuses: util.PackedArray(
            BlockStatus, unique_block_count) = undefined,

        pub fn initialize(self: *Self, start: usize) void {
            self.start = start;
            self.free_blocks.initialize(start);
            self.block_statuses.reset();
            self.block_statuses.set(0, .free) catch unreachable;
        }

        fn level_to_block_size(level: usize) usize {
            return max_size / (usize(1) << @truncate(UsizeShift, level));
        }

        fn block_size_to_level(size: usize) usize {
            return level_count - util.int_log2(usize, size / min_size) - 1;
        }

        fn unique_id(level: usize, index: usize) usize {
            return (usize(1) << @truncate(UsizeShift, level)) + index - 1;
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
            return if (index % 2) (index - 1) else (index + 1);
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
                level, index, .free);

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
            try self.block_statuses.set(this_unique_id, BlockStatus.split);
            try self.block_statuses.set(
                unique_id(new_level, new_index), BlockStatus.free);
            try self.block_statuses.set(
                unique_id(new_level, buddy_index), BlockStatus.free);
        }

        pub fn alloc(self: *Self, size: usize) Error!usize {
            if (size < min_size) {
                return Error.RequestedSizeTooSmall;
            }
            if (size > max_size) {
                return Error.RequestedSizeTooLarge;
            }

            const target_size = util.pow2_round_up(usize, size);
            const target_level = block_size_to_level(target_size);

            // Figure out how many (if any) levels we need to split a block in
            // to get a free block in our target level.
            var address_maybe: ?FreeBlock.Ptr = null;
            var level = target_level;
            while (true) {
                address_maybe = try self.free_blocks.get(level);
                if (address_maybe != null) {
                    break;
                }
                if (level == 0) {
                    return Error.OutOfMemory;
                }
                level -= 1;
            }

            // If we need to split blocks, do that
            var split_level = level;
            while (split_level != target_level) {
                try self.split(split_level, self.get_index(split_level, address_maybe.?));
                split_level += 1;
                address_maybe = try self.free_blocks.get(split_level);
                if (address_maybe == null) {
                    return Error.InternalError;
                }
            }

            // Reserve it
            const address = address_maybe.?;
            self.free_blocks.remove_block(target_level, address);
            const index = self.get_index(target_level, address);
            const id = unique_id(target_level, index);
            try self.block_statuses.set(id, .used);

            return @ptrToInt(address);
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
    var memory: [size]u8 = undefined;
    b.initialize(@ptrToInt(&memory));
    {
        const s = 32;
        const p = @intToPtr([*]u8, try b.alloc(s));
        @memset(p, 0x01, s);
    }
    {
        const s = 32;
        const p = @intToPtr([*]u8, try b.alloc(s));
        @memset(p, 0x04, s);
    }
    {
        const s = 64;
        const p = @intToPtr([*]u8, try b.alloc(s));
        @memset(p, 0xff, s);
    }
    const expected =
        "\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01" ++
        "\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01" ++
        "\x04\x04\x04\x04\x04\x04\x04\x04\x04\x04\x04\x04\x04\x04\x04\x04" ++
        "\x04\x04\x04\x04\x04\x04\x04\x04\x04\x04\x04\x04\x04\x04\x04\x04" ++
        "\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff" ++
        "\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff" ++
        "\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff" ++
        "\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff";
    std.testing.expectEqualSlices(u8, expected[0..], memory[0..]);
}
