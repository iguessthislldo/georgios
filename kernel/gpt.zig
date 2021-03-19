const std = @import("std");
const bytesAsSlice = std.mem.bytesAsSlice;

const util = @import("util.zig");
const Guid = @import("guid.zig");
const io = @import("io.zig");
const constant_guids = @import("constant_guids.zig");

pub const Error = error {
    InvalidMbr,
    InvalidGptHeader,
} || Guid.Error || io.BlockError;

pub const Mbr = struct {
    const Part = packed struct {
        status: u8,
        chs_start: u24,
        partition_type: u8,
        chs_end: u24,
        lba_start: u32,
        sector_count: u32,
    };

    const magic: u16 = 0xaa55;
    const gpt_protective_type: u8 = 0xEE;

    signature: u32 = undefined,
    partitions: [4]Part = undefined,
    gpt_protective: bool = undefined,

    pub fn new(block: []const u8) Error!Mbr {
        var mbr = Mbr{};

        // Check MBR "Boot Signature" (magic)
        if (bytesAsSlice(u16, block)[255] != magic) {
            return Error.InvalidMbr;
        }

        mbr.signature = bytesAsSlice(u32, block)[110];
        const partitions = @ptrCast([*]const Part,
            @alignCast(@alignOf(Part), &block[446]))[0..4];
        for (partitions) |*partition, i| {
            mbr.partitions[i] = partition.*;
        }
        mbr.gpt_protective =
            partitions[0].partition_type == gpt_protective_type;

        return mbr;
    }
};

pub const Partition = struct {
    type_guid: Guid,
    start: io.AddressType,
    end: io.AddressType,

    pub fn is_linux(self: *const Partition) bool {
        return self.type_guid.equals(&constant_guids.linux_partition_type);
    }
};

pub const Disk = struct {
    const magic = "EFI PART";

    block_store: *io.BlockStore = undefined,
    guid: Guid = undefined,
    partition_entries_lba: io.AddressType = undefined,
    partition_entry_size: usize = undefined,

    pub fn new(block_store: *io.BlockStore) Error!Disk {
        var disk = Disk{.block_store = block_store};

        // Check to see if there's a MBR and it says this is a GPT disk.
        var mbr_block = io.Block{.address = 0};
        try block_store.read_block(&mbr_block);
        defer (block_store.free_block(&mbr_block) catch unreachable);
        const mbr = try Mbr.new(mbr_block.data.?);
        if (!mbr.gpt_protective) {
            return Error.InvalidGptHeader;
        }

        // Get GPT Header Block
        var gpt_block = io.Block{.address = 1};
        try block_store.read_block(&gpt_block);
        defer (block_store.free_block(&gpt_block) catch unreachable);
        const block = gpt_block.data.?;

        // Check Magic
        for (block[0..magic.len]) |*ptr, i| {
            if (ptr.* != magic[i]) {
                return Error.InvalidGptHeader;
            }
        }

        // Get Info
        try disk.guid.from_ms(block[0x38..0x48]);
        disk.partition_entries_lba = @as(io.AddressType,
            bytesAsSlice(u64, block[0x48..0x50])[0]);
        disk.partition_entry_size = bytesAsSlice(u32, block[0x54..0x58])[0];

        return disk;
    }

    pub fn partitions(self: *const Disk) Error!PartitionIterator {
        var it = PartitionIterator{
            .block_store = self.block_store,
            .block = io.Block{.address = self.partition_entries_lba},
            .entry_size = self.partition_entry_size,
        };
        try self.block_store.read_block(&it.block);
        return it;
    }

    pub const PartitionIterator = struct {
        offset: usize = 0,
        block_store: *io.BlockStore,
        block: io.Block,
        entry_size: usize,

        pub fn next(self: *PartitionIterator) Error!?Partition {
            var partition: Partition = undefined;
            const id_offset = self.offset + 16;
            try partition.type_guid.from_ms(self.block.data.?[self.offset..id_offset]);
            if (partition.type_guid.is_null()) {
                return null;
            }
            const start_lba_offset = id_offset + 16;
            const end_lba_offset = start_lba_offset + 8;
            partition.start = @as(io.AddressType,
                bytesAsSlice(u64, self.block.data.?[start_lba_offset..end_lba_offset])[0]);
            const attributes_offset = end_lba_offset + 8;
            partition.end = @as(io.AddressType,
                bytesAsSlice(u64, self.block.data.?[end_lba_offset..attributes_offset])[0]);
            const name_offset = attributes_offset + 8;
            const supported_end = name_offset + 72;
            // Add any ammount we are over the entry size
            self.offset = supported_end + self.entry_size - (supported_end - self.offset);
            return partition;
        }

        pub fn done(self: *PartitionIterator) Error!void {
            try self.block_store.free_block(&self.block);
        }
    };
};
