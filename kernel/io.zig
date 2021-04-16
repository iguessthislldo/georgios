const utils = @import("utils");
const memory = @import("memory.zig");
const Allocator = memory.Allocator;
const MemoryError = memory.MemoryError;
const MappedList = @import("mapped_list.zig").MappedList;
const print = @import("print.zig");

usingnamespace @import("georgios").io;

pub const BlockError = error {
    InvalidBlockSize,
} || FileError || MemoryError;

pub const AddressType = u64;

fn address_eql(a: AddressType, b: AddressType) bool {
    return a == b;
}

fn address_cmp(a: AddressType, b: AddressType) bool {
    return a > b;
}

pub const Block = struct {
    address: AddressType,
    data: ?[]u8 = null,
};

/// Abstract Block IO Interface
pub const BlockStore = struct {
    const Self = @This();

    block_size: AddressType,
    read_block_impl: fn(*BlockStore, *Block) BlockError!void = default.read_block_impl,
    free_block_impl: fn(*BlockStore, *Block) BlockError!void = default.free_block_impl,

    pub const default = struct {
        pub fn read_block_impl(*BlockStore, *Block) BlockError!void {
            return BlockError.Unsupported;
        }

        pub fn free_block_impl(*BlockStore, *Block) BlockError!void {
            // Nop
        }
    };

    pub fn read_block(self: *BlockStore, block: *Block) BlockError!void {
        try self.read_block_impl(self, block);
    }

    pub fn free_block(self: *BlockStore, block: *Block) BlockError!void {
        try self.free_block_impl(self, block);
        block.data = null;
    }

    pub fn read(self: *BlockStore, address: AddressType, to: []u8) BlockError!void {
        const start_block = address / self.block_size;
        const block_count = utils.div_round_up(
            AddressType, @intCast(AddressType, to.len), self.block_size);
        const end_block = start_block + block_count;
        var block_address = start_block;
        var dest_offset: usize = 0;
        var src_offset = @intCast(usize, address % self.block_size);
        while (block_address < end_block) {
            var block = Block{.address = block_address};
            try self.read_block(&block);
            const new_dest_offset = dest_offset + utils.min(usize,
                @intCast(usize, self.block_size), to.len - dest_offset);
            _ = utils.memory_copy_truncate(
                to[dest_offset..new_dest_offset], block.data.?[src_offset..]);
            src_offset = 0;
            dest_offset = new_dest_offset;
            block_address += 1;
        }
    }
};

/// Cached Block IO Interface
///
/// TODO: Use Slab Alloc for MappedList, Pages for Block Data?
pub const CachedBlockStore = struct {
    const Self = @This();
    const Cache = MappedList(AddressType, Block, address_eql, address_cmp);

    alloc: *Allocator = undefined,
    real_block_store: *BlockStore = undefined,
    max_block_count: usize = undefined,
    cache: Cache = undefined,
    block_store: BlockStore = undefined,

    pub fn init(self: *Self, alloc: *Allocator,
            real_block_store: *BlockStore, max_block_count: usize) void {
        self.alloc = alloc;
        self.real_block_store = real_block_store;
        self.max_block_count = max_block_count;
        self.cache = Cache{.alloc = alloc};
        self.block_store.block_size = real_block_store.block_size;
        self.block_store.read_block_impl = Self.read_block_impl;
        self.block_store.free_block_impl = Self.free_block_impl;
    }

    fn read_block_impl(block_store: *BlockStore, block: *Block) BlockError!void {
        const self = @fieldParentPtr(Self, "block_store", block_store);
        if (self.cache.find_bump_to_front(block.address)) |cached_block| {
            block.* = cached_block;
            return;
        }
        try self.real_block_store.read_block(block);
        try self.cache.push_front(block.address, block.*);
        if (self.cache.len() > self.max_block_count) {
            if (try self.cache.pop_back()) |popped| {
                // print.format("Popping block at {} out of the cache\n", popped.address);
                var block_copy = popped;
                try self.real_block_store.free_block(&block_copy);
            } else {
                @panic("Cache is full, but null pop_back?");
            }
        }
    }

    fn free_block_impl(block_store: *BlockStore, block: *Block) BlockError!void {
        const self = @fieldParentPtr(Self, "block_store", block_store);
        try self.real_block_store.free_block(block);
    }
};
