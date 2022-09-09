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

const std = @import("std");

const memory = @import("memory.zig");
const Allocator = memory.Allocator;
const MemoryError = memory.MemoryError;
const AllocError = memory.AllocError;
const FreeError = memory.FreeError;
const utils = @import("utils");
const print = @import("print.zig");

const BlockStatus = enum(u2) {
    Invalid = 0,
    Split,
    Free,
    Used,
};

const Error = error {
    WrongBlockStatus,
    CantReserveAlreadyUsed,
} || utils.Error;

const FreeBlock = struct {
    const ConstPtr = *allowzero const FreeBlock;
    const Ptr = *allowzero FreeBlock;
    prev: ?Ptr,
    next: ?Ptr,
};
const free_block_size: usize = @sizeOf(FreeBlock);

const FreeBlockKind = enum {
    InSelf,
    InManagedArea,
};

pub fn MinBuddyAllocator(max_size_arg: usize) type {
    return BuddyAllocator(max_size_arg, free_block_size, .InManagedArea);
}

// max_size_arg is the size of the managed area and therefore the size of the
// largest possible allocation. min_size is the size of the smallest posible.
// allocation kind is where to store the free block list.
pub fn BuddyAllocator(max_size_arg: usize, min_size: usize, kind: FreeBlockKind) type {
    if (kind == .InManagedArea and min_size < free_block_size) {
        @panic("With InManagedArea BuddyAllocator min_size must be >= free_block_size");
    }
    return struct {
        const Self = @This();

        pub const max_size: usize = max_size_arg;

        const max_level_block_count = max_size / min_size;
        const level_count: usize = utils.int_log2(usize, max_level_block_count) + 1;
        const unique_block_count: usize = level_block_count(level_count) - 1;

        const FreeBlocks = struct {
            lists: [level_count]?FreeBlock.Ptr = .{null} ** level_count,

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

            fn dump_status(ba: *const Self, level: usize, index: usize) u8 {
                return switch (ba.block_statuses.get(unique_id(level, index)) catch unreachable) {
                    .Invalid => 'I',
                    .Split => 'S',
                    .Free => 'F',
                    .Used => 'U',
                };
            }

            fn dump(self: *FreeBlocks, ba: *const Self) void {
                var level: usize = 0;
                while (level < level_count) {
                    // Overview
                    {
                        std.debug.print("|", .{});
                        const space = (level_to_block_size(level) / min_size - 1) * 2;
                        const count = level_block_count(level);
                        var index: usize = 0;
                        while (index < count) {
                            std.debug.print("{c}", .{dump_status(ba, level, index)});
                            var i: usize = 0;
                            while (i < space) {
                                std.debug.print(" ", .{});
                                i += 1;
                            }
                            std.debug.print("|", .{});
                            index += 1;
                        }
                    }

                    // List
                    std.debug.print(" L{} ", .{level});
                    var block_maybe = self.lists[level];
                    while (block_maybe) |block| {
                        const index = ba.block_to_index(level, block);
                        std.debug.print("-> [{}({c})]", .{index, dump_status(ba, level, index)});
                        block_maybe = block.next;
                    }
                    std.debug.print("\n", .{});
                    level += 1;
                }
            }
        };

        const FreeBlocksInSelf = if (kind == .InSelf) [max_level_block_count]FreeBlock else void;
        pub const area_align: u29 = if (kind == .InManagedArea) @sizeOf(FreeBlock) else 1;
        pub const Area = []align(area_align) u8;

        allocator: Allocator = undefined,
        start: usize = undefined,
        free_blocks: FreeBlocks = undefined,
        free_blocks_in_self: FreeBlocksInSelf = undefined,
        block_statuses: utils.PackedArray(BlockStatus, unique_block_count) = undefined,

        pub fn init(self: *Self, area: Area) Error!void {
            self.allocator = Allocator{
                .alloc_impl = alloc,
                .free_impl = free,
            };
            if (area.len < max_size) {
                return Error.NotEnoughDestination;
            }
            self.start = @ptrToInt(area.ptr);
            self.free_blocks = .{};
            self.free_blocks.push(0, self.index_to_block(0, 0)) catch unreachable;
            self.block_statuses.reset();
            self.block_statuses.set(0, .Free) catch unreachable;
        }

        fn level_block_count(level: usize) usize {
            return @as(usize, 1) << @truncate(utils.UsizeLog2Type, level);
        }

        fn level_to_block_size(level: usize) usize {
            return max_size >> @truncate(utils.UsizeLog2Type, level);
        }

        fn size_to_level(size: usize) usize {
            const target_size = @maximum(min_size, utils.pow2_round_up(usize, size));
            return level_count - utils.int_log2(usize, target_size / min_size) - 1;
        }

        fn unique_id(level: usize, index: usize) usize {
            return level_block_count(level) + index - 1;
        }

        fn get_level_index(input_index: usize, level: usize, to_max: bool) usize {
            const shift = @intCast(utils.UsizeLog2Type, level_count - 1 - level);
            return if (to_max) input_index << shift else input_index >> shift;
        }

        fn in_self_offset(block: usize, start: usize) usize {
            return (block - start) / free_block_size;
        }

        fn block_to_index(self: *const Self, level: usize, block: FreeBlock.ConstPtr) usize {
            const b = @ptrToInt(block);
            const rv = switch (kind) {
                .InManagedArea => (b - self.start) / level_to_block_size(level),
                .InSelf => get_level_index(
                    in_self_offset(b, @ptrToInt(&self.free_blocks_in_self[0])), level, false),
            };
            return rv;
        }

        fn get_address(self: *Self, level: usize, index: usize) usize {
            return self.start + index * level_to_block_size(level);
        }

        fn get_block_raw(self: *Self, raw: usize) FreeBlock.Ptr {
            return switch (kind) {
                .InManagedArea => @intToPtr(FreeBlock.Ptr, raw),
                .InSelf => @ptrCast(FreeBlock.Ptr, &self.free_blocks_in_self[raw]),
            };
        }

        fn index_to_block(self: *Self, level: usize, index: usize) FreeBlock.Ptr {
            return self.get_block_raw(switch (kind) {
                .InManagedArea => self.get_address(level, index),
                .InSelf => get_level_index(index, level, true),
            });
        }

        fn address_to_block(self: *Self, address: usize) FreeBlock.Ptr {
            return self.get_block_raw(switch (kind) {
                .InManagedArea => blk: {
                    if (address % free_block_size != 0) {
                        @panic("address_to_block address isn't aligned to FreeBlock");
                    }
                    break :blk address;
                },
                .InSelf => in_self_offset(address, self.start),
            });
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

            const this_ptr = self.index_to_block(level, index);
            const new_level: usize = level + 1;
            const new_index = index << 1;
            const buddy_index = new_index + 1;
            const buddy_ptr = self.index_to_block(new_level, buddy_index);

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

        pub fn addr_in_range(self: *const Self, addr: usize) bool {
            return addr >= self.start and addr < (self.start + max_size);
        }

        pub fn slice_in_range(self: *const Self, range: []u8) bool {
            const addr = @ptrToInt(range.ptr);
            return self.addr_in_range(addr) and
                !(range.len > 1 and !self.addr_in_range(addr + range.len - 1));
        }

        fn reserve_block(self: *Self, level: usize, block: FreeBlock.Ptr) usize {
            self.free_blocks.remove_block(level, block);
            const index = self.block_to_index(level, block);
            const id = unique_id(level, index);
            self.block_statuses.set(id, .Used) catch unreachable;
            return index;
        }

        pub fn alloc(allocator: *Allocator, size: usize, align_to: usize) AllocError![]u8 {
            _ = align_to;
            const self = @fieldParentPtr(Self, "allocator", allocator);
            // TODO: Do we have to do something with align_to?

            if (size > max_size) {
                return AllocError.OutOfMemory;
            }

            const target_level = size_to_level(size);

            // Figure out how many (if any) levels we need to split a block in
            // to get a free block in our target level.
            var block: FreeBlock.Ptr = undefined;
            var level = target_level;
            while (true) {
                if (self.free_blocks.get(level) catch unreachable) |b| {
                    block = b;
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
                self.split(split_level, self.block_to_index(split_level, block)) catch unreachable;
                split_level += 1;
                block = (self.free_blocks.get(split_level) catch unreachable).?;
            }

            // Reserve it
            const index = self.reserve_block(target_level, block);

            const result = switch (kind) {
                .InManagedArea => @ptrCast([*]u8, block),
                .InSelf => @intToPtr([*]u8, self.get_address(target_level, index)),
            }[0..size];
            if (!self.slice_in_range(result)) {
                @panic("invalid alloc address");
            }
            return result;
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
            const this_ptr = self.index_to_block(level, index);
            const buddy_ptr = self.index_to_block(level, buddy_index);
            self.free_blocks.remove_block(level, this_ptr);
            self.free_blocks.remove_block(level, buddy_ptr);

            // Push New Block into List
            try self.free_blocks.push(new_level, self.index_to_block(new_level, new_index));

            // Set New Statuses
            try self.block_statuses.set(this_unique_id, .Invalid);
            try self.block_statuses.set(buddy_unique_id, .Invalid);
            try self.block_statuses.set(new_unique_id, .Free);
        }

        const BlockStatusIter = struct {
            ba: *Self,
            block: FreeBlock.Ptr,
            level: usize = level_count,
            index: usize = undefined,
            id: ?usize = null,

            fn next(self: *BlockStatusIter) ?BlockStatus {
                if (self.level == 0) return null;
                self.level -= 1;
                self.index = self.ba.block_to_index(self.level, self.block);
                self.block = self.ba.index_to_block(self.level, self.index); // Allow parent shift
                const id = unique_id(self.level, self.index);
                self.id = id;
                return self.ba.block_statuses.get(id) catch unreachable;
            }
        };

        fn free(allocator: *Allocator, value: []const u8, aligned_to: usize) FreeError!void {
            _ = aligned_to;
            const self = @fieldParentPtr(Self, "allocator", allocator);
            // TODO: Check aligned_to makes sense?

            if (value.len > max_size) return FreeError.InvalidFree;

            const address = @ptrToInt(value.ptr);
            const block = self.address_to_block(address);
            // TODO: This will issue a false positive if the allocated size
            // does not equal the size passed to free somewhat intentionally.
            // For example using std.ArrayList can have some extra capacity in
            // the allocation and freeing the result of toOwnedSlice can have a
            // different size from the original allocation.
            if (value.len > 0 and false) {
                const level = size_to_level(value.len);
                const index = self.block_to_index(level, block);
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
            var iter = BlockStatusIter{.ba = self, .block = block};
            while (iter.next()) |status| {
                if (status == .Used) {
                    break;
                }
            }
            const id = iter.id orelse return FreeError.InvalidFree;
            var level = iter.level;
            var index = iter.index;

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

        const AlignedRange = struct {
            ptr: usize,
            len: usize,

            fn end(self: *const AlignedRange) usize {
                return self.ptr + self.len;
            }
        };

        fn aligned_range(range: []u8) AlignedRange {
            const as_int = @ptrToInt(range.ptr);
            return switch (kind) {
                .InManagedArea => blk: {
                    const aligned = utils.align_down(as_int, free_block_size);
                    break :blk .{.ptr = aligned, .len = range.len + (as_int - aligned)};
                },
                .InSelf => .{.ptr = as_int, .len = range.len},
            };
        }

        fn block_is_free(self: *Self, address: usize, iter_ptr: ?*BlockStatusIter) ?usize {
            const block = self.address_to_block(address);
            var iter = BlockStatusIter{.ba = self, .block = block};
            defer if (iter_ptr) |ptr| {
                ptr.* = iter;
            };

            while (iter.next()) |status| {
                switch (status) {
                    .Free => return address + level_to_block_size(iter.level),
                    .Invalid => {},
                    else => break,
                }
            }
            return null;
        }

        pub fn is_free(self: *Self, range: []u8) bool {
            if (!self.slice_in_range(range)) {
                @panic("is_free got a range that's outside managed area!");
            }
            const aligned = aligned_range(range);
            var address = aligned.ptr;
            while (self.block_is_free(address, null)) |next| {
                if (next >= aligned.end()) {
                    return true;
                }
                address = next;
            }
            return false;
        }

        pub fn reserve(self: *Self, to_reserve: []u8) Error!void {
            if (!self.is_free(to_reserve)) return Error.CantReserveAlreadyUsed;
            const aligned = aligned_range(to_reserve);
            var block_start = aligned.ptr;
            var iter: BlockStatusIter = undefined;
            while (self.block_is_free(block_start, &iter)) |next| {
                var level = iter.level;
                var index = iter.index;
                block_start = self.get_address(level, index);
                if (block_start >= aligned.end()) {
                    break;
                }
                while (true) {
                    const block_size = level_to_block_size(level);
                    const range_end = aligned.ptr + aligned.len;
                    const middle = block_start + block_size / 2;
                    var split_right = false;
                    var split_left = false;
                    if (aligned.ptr >= middle) {
                        split_right = true;
                    }
                    if (range_end < middle) {
                        split_left = true;
                    }
                    if ((split_right or split_left) and level < (level_count - 1)) {
                        self.split(level, index) catch unreachable;
                        level += 1;
                        index = index * 2;
                        if (split_right) index += 1;
                        block_start = self.get_address(level, index);
                    } else {
                        break;
                    }
                }

                _ = self.reserve_block(level, self.index_to_block(level, index));

                if (next >= self.start + max_size) {
                    break;
                }
                block_start = next;
            }
        }

        pub fn dump(self: *Self) void {
            std.debug.print("Blocks : Free Lists " ++
                "============================================================\n", .{});
            self.free_blocks.dump(self);
            std.debug.print(
                \\Memory ========================================================================
                \\{}
                \\===============================================================================
                \\
                ,
                .{utils.fmt_dump_hex(@intToPtr([*]const u8, self.start)[0..max_size])});
        }
    };
}

const any_byte: u8 = 0x00;
fn expect_mem(expected: []const u8, actual: []const u8) !void {
    try std.testing.expectEqual(expected.len, actual.len);
    var fail = false;
    for (expected) |e, i| {
        if (e != any_byte and e != actual[i]) {
            fail = true;
            break;
        }
    }
    if (fail) {
        std.debug.print(
            \\Expected ======================================================================
            \\NOTE: 0x{x} matches any byte
            \\{}
            \\Actual ========================================================================
            \\{}
            \\===============================================================================
            \\
            ,
            .{any_byte, utils.fmt_dump_hex(expected), utils.fmt_dump_hex(actual)});
        try std.testing.expect(false);
    }
}

fn TestHelper(comptime kind: FreeBlockKind, total_size: usize) type {
    return struct {
        const Th = @This();
        const Ba = BuddyAllocator(total_size, free_block_size, kind);
        const in_self = kind == .InSelf;

        ba: Ba = .{},
        a: *Allocator = undefined,
        m: [total_size]u8 align(Ba.area_align) = undefined,

        fn init(self: *Th) !void {
            try self.ba.init(self.m[0..]);
            self.a = &self.ba.allocator;
        }

        fn assert_is_free(self: *Th, size: usize, at: usize, assert_free: bool) !void {
            // std.debug.print("assert_is_free {}@{} == {}\n", .{size, at, assert_free});
            try std.testing.expectEqual(assert_free, self.ba.is_free(
                @intToPtr([*]align(Ba.area_align) u8, self.ba.start)[at..at + size]));
        }

        fn alloc(self: *Th, size: usize, at: usize, fill: u8) ![]u8 {
            // std.debug.print(
            //     \\ALLOC #########################################################################
            //     \\Size: {} @ {} fill: {x}
            //     \\ BEFORE:
            //     \\
            //     ,
            //     .{size, at, fill});
            // self.ba.dump();
            try self.assert_is_free(size, at, true);
            const s = try self.ba.allocator.alloc_array(u8, size);
            for (s) |*e| e.* = fill;
            try self.assert_is_free(size, at, false);
            // std.debug.print(
            //     \\ALLOC AFTER ###################################################################
            //     \\
            //     , .{});
            // self.ba.dump();
            return s;
        }
    };
}

fn buddy_allocator_test(comptime kind: FreeBlockKind) !void {
    const ptr_size = utils.int_bit_size(usize);
    const free_pointer_size: usize = switch (ptr_size) {
        32 => @as(usize, 8),
        64 => @as(usize, 16),
        else => unreachable,
    };
    try std.testing.expectEqual(free_pointer_size, @sizeOf(?FreeBlock.Ptr));
    try std.testing.expectEqual(free_pointer_size * 2, free_block_size);

    const Th = TestHelper(kind, 256);
    var th = Th{};
    try th.init();
    try std.testing.expectEqual(switch (ptr_size) {
        32 => @as(usize, 5),
        64 => @as(usize, 4),
        else => unreachable,
    }, Th.Ba.level_count);

    try th.assert_is_free(th.m.len, 0, true);
    try th.assert_is_free(1, 1, true);
    const single = 32; // Single Block
    const ones = try th.alloc(single, 0, 0x11);
    try th.assert_is_free(th.m.len, 0, false);
    try th.assert_is_free(th.m.len - single, single, true);
    try th.assert_is_free(1, 1, false);

    const fours = try th.alloc(single, single, 0x44);

    const bs_index = 100;
    const bs = th.m[bs_index..150];
    try th.assert_is_free(bs.len, bs_index, true);
    try th.ba.reserve(bs);
    try th.assert_is_free(32, 64, true); // Before reserved
    try th.assert_is_free(bs.len, bs_index, false);
    try th.assert_is_free(96, 160, true); // After reserved
    for (bs) |*c| c.* = 0xbb;
    const ones_and_fours = "\x11" ** single ++ "\x44" ** single;
    const before_bs = [_]u8{any_byte} ** (bs_index - ones_and_fours.len);
    const after_bs_index = bs_index + bs.len;
    const after_bs = [_]u8{any_byte} ** (th.m.len - after_bs_index);
    const bs_and_before = ones_and_fours ++ before_bs ++ "\xbb" ** bs.len;
    try expect_mem(bs_and_before ++ after_bs, th.m[0..]);

    const fs_len = 64;
    const fs_index = 192;
    const fs = try th.alloc(fs_len, fs_index, 0xff);
    const before_fs = [_]u8{any_byte} ** (th.m.len - after_bs_index - fs_len);
    try expect_mem(bs_and_before ++ before_fs ++ "\xff" ** fs_len, th.m[0..]);

    const fives = try th.alloc(single, th.m.len - fs_len - single, 0x55);
    const sixes = try th.alloc(single, ones_and_fours.len, 0x66);

    try th.assert_is_free(fs_len, fs_index, false);
    try th.a.free_array(fs);
    try th.assert_is_free(fs_len, fs_index, true);

    {
        const byte: u8 = 0xaa;
        const as = try th.alloc(1, fs_index, byte);
        try std.testing.expectEqual(byte, th.m[fs_index]);
        try th.a.free_array(as);
    }

    const eights = try th.alloc(single, fs_index, 0x88);
    const sevens = try th.alloc(single, fs_index + single, 0x77);
    try expect_mem(bs_and_before ++ before_fs ++ "\x88" ** single ++ "\x77" ** single, th.m[0..]);

    try th.a.free_array(sevens);
    try th.a.free_array(ones);
    try th.a.free_array(eights);
    try th.a.free_array(sixes);
    try th.a.free_array(fours);
    try th.a.free_array(fives);
}

test "BuddyAllocator.InManagedArea" {
    try buddy_allocator_test(.InManagedArea);
}

test "BuddyAllocator.InSelf" {
    try buddy_allocator_test(.InSelf);
}
