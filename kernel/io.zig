const std = @import("std");
const Allocator = std.mem.Allocator;

const utils = @import("utils");

const georgios = @import("georgios");
const io = georgios.io;
pub const File = io.File;
pub const FileError = io.FileError;
pub const BufferFile = io.BufferFile;

pub const AddressType = u64;

pub const Block = struct {
    // NOTE: In BLOCKS, not bytes.
    address: AddressType,
    data: ?[]u8 = null,
};

/// Abstract Block I/O Interface
pub const BlockStore = struct {
    const Self = @This();

    page_alloc: Allocator,
    block_size: usize,
    max_address: ?AddressType = null,
    create_block_impl: fn(*BlockStore, *Block) FileError!void = alloc_data,
    destroy_block_impl: fn(*BlockStore, *Block) void = free_data,
    read_block_impl: fn(*BlockStore, *Block) FileError!void = default.read_block_impl,
    write_block_impl: fn(*BlockStore, *Block) FileError!void = default.write_block_impl,
    flush_impl: fn(*BlockStore) FileError!void = default.flush_impl,

    pub fn alloc_data(self: *BlockStore, block: *Block) FileError!void {
        if (block.data == null) {
            block.data = try self.page_alloc.alloc(u8, self.block_size);
        }
    }

    pub fn free_data(self: *BlockStore, block: *Block) void {
        if (block.data) |data| {
            self.page_alloc.free(data);
            block.data = null;
        }
    }

    pub fn create_block(self: *BlockStore, block: *Block) FileError!void {
        try self.create_block_impl(self, block);
    }

    pub fn destroy_block(self: *BlockStore, block: *Block) void {
        self.destroy_block_impl(self, block);
    }

    pub const default = struct {
        pub fn read_block_impl(self: *BlockStore, block: *Block) FileError!void {
            _ = self;
            _ = block;
            return FileError.Unsupported;
        }

        pub fn write_block_impl(self: *BlockStore, block: *Block) FileError!void {
            _ = self;
            _ = block;
            return FileError.Unsupported;
        }

        pub fn flush_impl(self: *BlockStore) FileError!void {
            _ = self;
        }
    };

    fn check_block(self: *const BlockStore, block: *const Block) FileError!void {
        if (self.max_address) |max_address| {
            if (block.address > max_address) return FileError.OutOfBounds;
        }
        if (block.data == null) {
            @panic("check_block: block.data is null");
        } else if (block.data.?.len != self.block_size) {
            @panic("check_block: block.data is the same size as the block size");
        }
    }

    pub fn read_block(self: *BlockStore, block: *Block) FileError!void {
        try self.check_block(block);
        try self.read_block_impl(self, block);
    }

    // NOTE: address is in BYTES, not blocks
    pub fn read(self: *BlockStore, address: AddressType, to: []u8) FileError!void {
        // Also note that Block.address is in blocks
        const start_block = address / self.block_size;
        var src_offset = @intCast(usize, address % self.block_size);
        const block_count = utils.div_round_up(AddressType,
            @intCast(AddressType, src_offset + to.len), self.block_size);
        const end_block = start_block + block_count;
        var dest_offset: usize = 0;
        var block = Block{.address = start_block};
        try self.create_block(&block);
        defer self.destroy_block(&block);
        while (block.address < end_block) {
            const size = @minimum(
                @intCast(usize, self.block_size) - src_offset, to.len - dest_offset);
            try self.read_block(&block);
            const new_dest_offset = dest_offset + size;
            _ = utils.memory_copy_truncate(
                to[dest_offset..new_dest_offset], block.data.?[src_offset..]);
            src_offset = 0;
            dest_offset = new_dest_offset;
            block.address += 1;
        }
    }

    pub fn expect_read(self: *BlockStore,
            address: AddressType, expected: []const u8, buffer: []u8) !void {
        try self.read(address, buffer);
        try utils.expect_equal_bytes(expected, buffer);
    }

    pub fn write_block(self: *BlockStore, block: *Block) FileError!void {
        try self.check_block(block);
        try self.write_block_impl(self, block);
    }

    // NOTE: address is in BYTES, not blocks
    pub fn write_for_test(self: *BlockStore, address: AddressType, data: []const u8) FileError!void {
        var block = Block{.address = address};
        try self.create_block(&block);
        defer self.destroy_block(&block);
        if (data.len < self.block_size) {
            for (block.data.?[data.len..]) |*b| {
                b.* = 0;
            }
        }
        _ = utils.memory_copy_truncate(block.data.?, data);
        try self.write_block(&block);
    }

    pub fn flush(self: *BlockStore) FileError!void {
        try self.flush_impl(self);
    }
};

pub fn simple_block_store_test(alloc: Allocator, bs: *BlockStore, block_count: usize) !void {
    if (block_count < 3) @panic("simple_block_store_test: block_count needs to be at least 3");
    var block = Block{.address = 0};
    try bs.create_block(&block);
    defer bs.destroy_block(&block);

    // Write in whole blocks
    const Int = u16;
    var int: Int = 0;
    while (block.address < block_count) {
        for (std.mem.bytesAsSlice(Int, block.data.?)) |*value| {
            value.* = int;
            int += 1;
        }
        try bs.write_block(&block);
        block.address += 1;
    }

    // Read in whole blocks
    block.address = 0;
    int = 0;
    while (block.address < block_count) {
        try bs.read_block(&block);
        for (std.mem.bytesAsSlice(Int, block.data.?)) |value| {
            try std.testing.expectEqual(int, value);
            int += 1;
        }
        block.address += 1;
    }

    // Read partial blocks (Ending half of block, whole block, starting half of block)
    const expected = try alloc.alloc(u8, bs.block_size * 2);
    defer alloc.free(expected);
    for (std.mem.bytesAsSlice(Int, expected)) |*value, i| {
        value.* = @intCast(u16, i + bs.block_size / @sizeOf(Int) / 2);
    }
    const partial_blocks = try alloc.alloc(u8, bs.block_size * 2);
    defer alloc.free(partial_blocks);
    try bs.read(bs.block_size / 2, partial_blocks);
    for (std.mem.bytesAsSlice(Int, partial_blocks)) |value, i| {
        try std.testing.expectEqual(@intCast(u16, i + bs.block_size / @sizeOf(Int) / 2), value);
    }
}

/// BlockStore that stores blocks in memory, optionally as cache to another
/// BlockStore.
pub const MemoryBlockStore = struct {
    const BlockInfo = struct {
        block: Block,
        changed: bool = false,
        list_node: ?*BlockList.Node = null,
    };
    const BlockList = utils.List(*BlockInfo);
    const BlockMap = std.AutoHashMap(AddressType, *BlockInfo);

    alloc: Allocator = undefined,
    cached_block_store: ?*BlockStore = null,
    cached_block_limit: ?usize = null,
    block_map: BlockMap = undefined,
    block_list: BlockList = undefined,
    block_store_if: BlockStore = undefined,

    pub fn init(self: *MemoryBlockStore,
            alloc: Allocator, page_alloc: Allocator, block_size: usize) void {
        self.alloc = alloc;
        self.block_map = BlockMap.init(alloc);
        self.block_list = .{.alloc = alloc};
        self.block_store_if = .{
            .page_alloc = page_alloc,
            .block_size = block_size,
            .create_block_impl = create_block_impl,
            .destroy_block_impl = destroy_block_impl,
            .read_block_impl = read_block_impl,
            .write_block_impl = write_block_impl,
            .flush_impl = flush_impl,
        };
    }

    pub fn init_as_cache(self: *MemoryBlockStore,
            alloc: Allocator, cached_block_store: *BlockStore, limit: usize) void {
        self.init(alloc, undefined, cached_block_store.block_size);
        self.cached_block_store = cached_block_store;
        self.cached_block_limit = limit;
        self.block_store_if.max_address = cached_block_store.max_address;
        // TODO: Preallocate capacity for block_map?
        // TODO: Preallocate block data for block_map?
    }

    pub fn clear(self: *MemoryBlockStore) void {
        var it = self.block_map.iterator();
        while (it.next()) |kv| {
           self.block_store_if.destroy_block(&kv.value_ptr.*.block);
           self.alloc.destroy(kv.value_ptr.*);
        }
        self.block_map.clearAndFree();
        self.block_list.clear();
    }

    pub fn done(self: *MemoryBlockStore) void {
        self.clear();
        self.block_map.deinit();
    }

    fn create_block_impl(bs: *BlockStore, block: *Block) FileError!void {
        const self = @fieldParentPtr(MemoryBlockStore, "block_store_if", bs);
        if (self.cached_block_store) |cached_block_store| {
            try cached_block_store.create_block(block);
        } else {
            try self.block_store_if.alloc_data(block);
        }
    }

    fn destroy_block_impl(bs: *BlockStore, block: *Block) void {
        const self = @fieldParentPtr(MemoryBlockStore, "block_store_if", bs);
        if (self.cached_block_store) |cached_block_store| {
            cached_block_store.destroy_block(block);
        } else {
            self.block_store_if.free_data(block);
        }
    }

    fn flush_block(self: *MemoryBlockStore, block_info: *BlockInfo) FileError!void {
        if (block_info.changed) {
            try self.cached_block_store.?.write_block(&block_info.block);
            block_info.changed = false;
        }
    }

    fn flush_impl(bs: *BlockStore) FileError!void {
        const self = @fieldParentPtr(MemoryBlockStore, "block_store_if", bs);
        if (self.cached_block_store) |cached_block_store| {
            var it = self.block_map.iterator();
            while (it.next()) |kv| {
                try self.flush_block(kv.value_ptr.*);
            }
            try cached_block_store.flush();
        }
    }

    const GetBlockMode = enum {
        GetForRead,
        GetOrCreateForRead,
        GetOrCreateForWrite,
    };

    const GetBlockResult = struct {
        block: ?*Block = null,
        created: bool = false,
    };

    pub fn block_count(self: *const MemoryBlockStore) usize {
        return self.block_map.count();
    }

    fn get_block(self: *MemoryBlockStore,
            address: AddressType, mode: GetBlockMode) FileError!GetBlockResult {
        // TODO: Optimize if cached is returning all zeros?
        var result = GetBlockResult{};
        if (mode == .GetForRead) {
            result.block =
                if (self.block_map.getPtr(address)) |block_info| &block_info.*.block else null;
            return result;
        }
        const r = try self.block_map.getOrPut(address);
        const block_info_ptr_ptr = r.value_ptr;
        var block_info: *BlockInfo = undefined;
        result.created = !r.found_existing;
        if (result.created) {
            block_info = try self.alloc.create(BlockInfo);
            block_info.* = .{.block = .{.address = address}};
            block_info_ptr_ptr.* = block_info;
            if (self.cached_block_store) |cached_block_store| {
                // If there's too many blocked stored then flush and discard
                // the oldest one.
                if (self.block_count() > self.cached_block_limit.?) {
                    const popped_block_info = self.block_list.pop_back().?;
                    const popped_block = &popped_block_info.block;
                    try self.flush_block(popped_block_info);
                    cached_block_store.destroy_block(popped_block);
                    _ = self.block_map.remove(popped_block.address);
                    self.alloc.destroy(popped_block_info);
                }
                try self.block_list.push_front(block_info);
                block_info.list_node = self.block_list.head.?;
            }
            try self.block_store_if.create_block(&block_info.block);
        } else {
            block_info = block_info_ptr_ptr.*;
            if (self.cached_block_store != null) {
                self.block_list.bump_node_to_front(block_info.list_node.?);
            }
        }
        if (mode == .GetOrCreateForWrite) block_info.changed = true;
        result.block = &block_info.block;
        return result;
    }

    fn read_block_impl(bs: *BlockStore, block: *Block) FileError!void {
        const self = @fieldParentPtr(MemoryBlockStore, "block_store_if", bs);
        const result = try self.get_block(block.address,
            if (self.cached_block_store == null) .GetForRead else .GetOrCreateForRead);
        if (result.block) |stored_block| {
            if (result.created) {
                try self.cached_block_store.?.read_block(stored_block);
            }
            _ = try utils.memory_copy_error(block.data.?, stored_block.data.?);
        } else {
            for (block.data.?) |*byte| {
                byte.* = 0;
            }
        }
    }

    fn write_block_impl(bs: *BlockStore, block: *Block) FileError!void {
        const self = @fieldParentPtr(MemoryBlockStore, "block_store_if", bs);
        const stored_block = (try self.get_block(block.address, .GetOrCreateForWrite)).block.?;
        _ = try utils.memory_copy_error(stored_block.data.?, block.data.?);
    }
};

fn memory_block_store_test(mbs: *MemoryBlockStore, cached_mbs: ?*MemoryBlockStore) !void {
    const expectEqual = std.testing.expectEqual;

    const bs = &mbs.block_store_if;
    const block_size = bs.block_size;
    _ = cached_mbs;

    try expectEqual(@as(usize, 0), mbs.block_count());

    // Make sure we read zeros before anything is written.
    {
        var e = [_]u8{0} ** 4;
        var b: [e.len]u8 = undefined;
        try bs.expect_read(0, e[0..], b[0..]);
    }
    {
        //      VVV V
        // 01234567 89abcdef
        var e = [_]u8{0} ** 4;
        var b: [e.len]u8 = undefined;
        try bs.expect_read(5, e[0..], b[0..]);
    }
    {
        var e = [_]u8{0} ** 18;
        var b: [e.len]u8 = undefined;
        try bs.expect_read(0, e[0..], b[0..]);
    }

    if (cached_mbs) |cmbs| {
        try expectEqual(@as(usize, 3), mbs.block_count());
        try expectEqual(@as(usize, 0), cmbs.block_count());
        // Nothing's been changed yet, so flushing the cache shouldn't add
        // blocks to the underlying store.
        try bs.flush();
        try expectEqual(@as(usize, 0), cmbs.block_count());
    } else {
        try expectEqual(@as(usize, 0), mbs.block_count());
    }

    // Can read and write data.
    {
        var e = [_]u8{0} ** 16;
        for (e) |*b, i| {
            b.* = @truncate(u8, i);
        }
        try bs.write_for_test(0, e[0..8]);
        try bs.write_for_test(1, e[8..16]);
        var b: [e.len]u8 = undefined;
        try bs.expect_read(0, e[0..], b[0..]);
    }
    {
        //      VVV V
        // 01234567 89abcdef
        var e = [_]u8{5, 6, 7, 8};
        var b: [e.len]u8 = undefined;
        try bs.expect_read(5, e[0..], b[0..]);
    }

    if (cached_mbs) |cmbs| {
        try expectEqual(@as(usize, 3), mbs.block_count());
        try expectEqual(@as(usize, 0), cmbs.block_count());
        try bs.flush();
        try expectEqual(@as(usize, 2), cmbs.block_count());
    } else {
        try expectEqual(@as(usize, 2), mbs.block_count());
    }

    // Reading just past the written blocks should return zeros.
    {
        var e = [_]u8{0} ** 8;
        var b: [e.len]u8 = undefined;
        try bs.expect_read(block_size * 2, e[0..], b[0..]);
    }
    // But setting a max address and trying again should cause an error.
    bs.max_address = 1;
    {
        var e = [_]u8{0} ** 8;
        try std.testing.expectError(FileError.OutOfBounds, bs.write_for_test(2, e[0..]));
        var b: [e.len]u8 = undefined;
        try std.testing.expectError(FileError.OutOfBounds, bs.read(block_size * 2, b[0..]));
    }
    bs.max_address = null;

    if (cached_mbs) |cmbs| {
        try expectEqual(@as(usize, 3), mbs.block_count());
        try expectEqual(@as(usize, 2), cmbs.block_count());

        // Block 2 is at front, but reading 1 will bring it back to the front again
        try expectEqual(@as(AddressType, 2), mbs.block_list.front().?.block.address);
        try expectEqual(@as(AddressType, 1), mbs.block_list.head.?.next.?.value.block.address);
        {
            var e = [_]u8{0} ** 8;
            for (e) |*b, i| {
                b.* = @truncate(u8, i + 8);
            }
            var b: [e.len]u8 = undefined;
            try bs.expect_read(8, e[0..], b[0..]);
        }
        try expectEqual(@as(AddressType, 1), mbs.block_list.front().?.block.address);

        // Writing past the cache limit will flush the oldest block from mbs to
        // cmbs and discard it.
        {
            var e = [_]u8{0} ** 16;
            for (e) |*b, i| {
                b.* = @truncate(u8, 0x10 + i);
            }
            try bs.write_for_test(3, e[0..8]);
            try expectEqual(@as(usize, 4), mbs.block_count());
            try expectEqual(@as(usize, 2), cmbs.block_count());
            try bs.flush();
            try expectEqual(@as(usize, 3), cmbs.block_count());
            // Block 0 should be next to be discarded
            try expectEqual(@as(AddressType, 0), mbs.block_list.back().?.block.address);
            try bs.write_for_test(4, e[8..16]);
            try expectEqual(@as(usize, 4), mbs.block_count());
            try expectEqual(@as(usize, 3), cmbs.block_count());
            try bs.flush();
            try expectEqual(@as(usize, 4), cmbs.block_count());
        }

        // Block 0 was discarded, now 4 is at the front and 2 is at the back
        try expectEqual(@as(AddressType, 4), mbs.block_list.front().?.block.address);
        try expectEqual(@as(AddressType, 2), mbs.block_list.back().?.block.address);
        // Write to 2 to bring it to the front
        const hello = " Hello! ";
        try bs.write_for_test(2, hello);
        try expectEqual(@as(AddressType, 2), mbs.block_list.front().?.block.address);
        try std.testing.expectEqualStrings(hello, mbs.block_list.front().?.block.data.?);

        // Do read from the flushed and discarded block 0
        {
            const e = "\x00\x01\x02\x03\x04\x05\x06\x07";
            var b: [e.len]u8 = undefined;
            try bs.expect_read(0, e[0..], b[0..]);
        }
        try expectEqual(@as(AddressType, 0), mbs.block_list.front().?.block.address);
    } else {
        try expectEqual(@as(usize, 2), mbs.block_count());
    }
}

test "MemoryBlockStore" {
    var ta = utils.TestAlloc{};
    defer ta.deinit(.Panic);
    errdefer ta.deinit(.NoPanic);
    const alloc = ta.alloc();

    var mbs = MemoryBlockStore{};
    mbs.init(alloc, alloc, 8);
    defer mbs.done();
    try memory_block_store_test(&mbs, null);
    try simple_block_store_test(alloc, &mbs.block_store_if, 16);
}

test "MemoryBlockStore as cache" {
    var ta = utils.TestAlloc{};
    defer ta.deinit(.Panic);
    errdefer ta.deinit(.NoPanic);
    const alloc = ta.alloc();

    var mbs = MemoryBlockStore{};
    mbs.init(alloc, alloc, 8);
    defer mbs.done();

    var cache = MemoryBlockStore{};
    cache.init_as_cache(alloc, &mbs.block_store_if, 4);
    defer cache.done();

    try memory_block_store_test(&cache, &mbs);
    try simple_block_store_test(alloc, &cache.block_store_if, 16);
}

pub const StdFileBlockStore = struct {
    file: *const std.fs.File = undefined,
    block_store_if: BlockStore = undefined,

    pub fn init(self: *StdFileBlockStore,
            page_alloc: Allocator, file: *const std.fs.File, block_size: usize) void {
        self.* = .{
            .file = file,
            .block_store_if = .{
                .page_alloc = page_alloc,
                .block_size = block_size,
                .read_block_impl = read_block_impl,
                .write_block_impl = write_block_impl,
            },
        };
    }

    fn seek_to(self: *StdFileBlockStore, block: *Block) FileError!void {
        const stream = self.file.seekableStream();
        stream.seekTo(block.address * self.block_store_if.block_size)
            catch return FileError.OutOfBounds;
    }

    fn read_block_impl(bs: *BlockStore, block: *Block) FileError!void {
        const self = @fieldParentPtr(StdFileBlockStore, "block_store_if", bs);
        try self.seek_to(block);
        _ = self.file.reader().read(block.data.?) catch return FileError.Internal;
    }

    fn write_block_impl(bs: *BlockStore, block: *Block) FileError!void {
        const self = @fieldParentPtr(StdFileBlockStore, "block_store_if", bs);
        try self.seek_to(block);
        _ = self.file.writer().write(block.data.?) catch return FileError.Internal;
    }
};

test "StdFileBlockStore read only" {
    var ta = utils.TestAlloc{};
    defer ta.deinit(.Panic);
    errdefer ta.deinit(.NoPanic);
    const alloc = ta.alloc();

    const dir: std.fs.Dir = std.fs.cwd();
    const file = try dir.openFile("kernel/io.zig", .{});
    defer file.close();

    const block_size = 32;
    const end = block_size * 2;
    var fbs = StdFileBlockStore{};
    fbs.init(alloc, &file, block_size);

    const file_contents = @embedFile("io.zig");
    const fc0 = file_contents[0..block_size];
    const fc1 = file_contents[block_size..end];
    const fc01 = file_contents[0..end];

    var buffer: [end]u8 = undefined;
    const b0 = buffer[0..block_size];
    const b1 = buffer[block_size..end];
    const b01 = buffer[0..end];

    try fbs.block_store_if.read(0, b0);
    try std.testing.expectEqualStrings(fc0, b0);

    try fbs.block_store_if.read(block_size, b1);
    try std.testing.expectEqualStrings(fc1, b1);

    try fbs.block_store_if.read(0, b01);
    try std.testing.expectEqualStrings(fc01, b01);
}

test "StdFileBlockStore read and write" {
    var ta = utils.TestAlloc{};
    defer ta.deinit(.Panic);
    errdefer ta.deinit(.NoPanic);
    const alloc = ta.alloc();

    const dir: std.fs.Dir = std.fs.cwd();
    const file = try dir.createFile("tmp/StdFileBlockStore-test", .{.read = true});
    defer file.close();

    const block_size = 32;
    var fbs = StdFileBlockStore{};
    fbs.init(alloc, &file, block_size);
    try simple_block_store_test(alloc, &fbs.block_store_if, block_size);
}
