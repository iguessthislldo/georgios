// Second Extended File System (Ext2)
//
// For Refernce See:
//   https://en.wikipedia.org/wiki/Ext2
//   https://wiki.osdev.org/Ext2
//   https://www.nongnu.org/ext2-doc/ext2.html

const util = @import("util.zig");
const print = @import("print.zig");
const Allocator = @import("memory.zig").Allocator;
const MemoryError = @import("memory.zig").MemoryError;

const read_from_drive = @import("platform.zig").impl.ata.read_from_drive;

const Superblock = packed struct {
    const expected_magic: u16 = 0xef53;

    // Rev0 Superblock
    inode_count: u32 = 0,
    block_count: u32 = 0,
    superuser_block_count: u32 = 0,
    free_block_count: u32 = 0,
    free_inode_count: u32 = 0,
    first_data_block: u32 = 0,
    log_block_size: u32 = 0,
    log_frag_size: u32 = 0,
    blocks_per_group: u32 = 0,
    frags_per_group: u32 = 0,
    inodes_per_group: u32 = 0,
    last_mount_time: u32 = 0,
    last_write_time: u32 = 0,
    unchecked_mount_count: u16 = 0,
    max_unchecked_mount_count: u16 = 0,
    magic: u16 = 0,
    state: u16 = 0,
    error_repsponse: u16 = 0,
    minor_revision: u16 = 0,
    last_check_time: u32 = 0,
    check_interval: u32 = 0,
    creator_os: u32 = 0,
    major_revision: u32 = 0,
    superuser_uid: u16 = 0,
    superuser_gid: u16 = 0,
    // Start of Rev1 Superblock Extention
    first_nonreserved_inode: u32 = 0,
    inode_size: u32 = 0,
    // Rest have been left out for now

    pub fn verify(self: *const Superblock) void {
        if (self.magic != expected_magic) {
            @panic("Invalid Ext2 Magic");
        }
        if (self.major_revision != 1) {
            @panic("Invalid Ext2 Revision");
        }
        if ((util.align_up(self.inode_count, self.inodes_per_group) / self.inodes_per_group)
                != self.block_group_count()) {
            @panic("Inconsistent Ext2 Block Group Count");
        }
    }

    pub fn block_size(self: *const Superblock) usize {
        // TODO: Zig Bug? Can't inline util.Ki(1)
        return usize(1024) << @truncate(util.UsizeLog2Type, self.log_block_size);
    }

    pub fn block_group_count(self: *const Superblock) usize {
        return util.align_up(self.block_count, self.blocks_per_group) / self.blocks_per_group;
    }
};

const BlockGroupDescriptor = packed struct {
    block_bitmap: u32,
    inode_bitmap: u32,
    inode_table: u32,
    free_block_count: u16,
    free_inode_count: u16,
    used_dir_count: u16,
    pad: u16,
    reserved: [12]u8,
};

const Inode = packed struct {
    mode: u16,
    uid: u16,
    size: u32,
    last_access_time: u32,
    creation_time: u32,
    last_modification_time: u32,
    deletion_time: u32,
    gid: u16,
    link_count: u16,
    block_count: u32,
    flags: u32,
    os_dependant_field_1: u32,
    blocks: [15]u32,
    generation: u32,
    file_acl: u32,
    dir_acl: u32,
    fragment_address: u32,
    os_dependant_field_2: [12]u8,
};

pub const DataBlockIterator = struct {
    const max_first_level_index: u8 = 12;
    const second_level_index = max_first_level_index + 1;
    const third_level_index = second_level_index + 1;
    const fourth_level_index = third_level_index + 1;

    fs: *Ext2,
    inode: *Inode,
    // blocks_left: u8 = 0,
    first_level_pos: u8 = 0,
    second_level: ?[]u32 = null,
    second_level_pos: usize = 0,
    third_level: ?[]u32 = null,
    third_level_pos: usize = 0,
    fourth_level: ?[]u32 = null,
    fourth_level_pos: usize = 0,
    data_block: ?[]u8 = null,

    // pub fn initialize(self: *DataBlockIterator) void {
    //     self.blocks_left = util.align_up(self.inode.size, self.fs.block_size)
    //         / self.fs.block_size;
    // }

    fn get_next_block_index(self: *DataBlockIterator) MemoryError!u32 {
        // First Level
        if (self.first_level_pos <= max_first_level_index) {
            const rv = self.inode.blocks[self.first_level_pos];
            self.first_level_pos += 1;
            return rv;
        }

        // Figure Out Our Position, Allocating Levels As Needed
        var get_fourth_level = false;
        if (self.first_level_pos >= fourth_level_index) {
            if (self.fourth_level == null) {
                self.fourth_level = try self.fs.alloc.alloc_array(u32,
                    self.fs.block_size / @sizeOf(u32));
                get_fourth_level = true;
            }
            if (self.fourth_level_pos >= self.fs.max_entries_per_block) {
                self.third_level_pos += 1;
                self.fourth_level_pos = 0;
                get_fourth_level = true;
            }
        }
        var get_third_level = false;
        if (self.first_level_pos >= third_level_index) {
            if (self.third_level == null) {
                self.third_level = try self.fs.alloc.alloc_array(u32,
                    self.fs.block_size / @sizeOf(u32));
                get_third_level = true;
            }
            if (self.third_level_pos >= self.fs.max_entries_per_block) {
                self.second_level_pos += 1;
                self.third_level_pos = 0;
                get_third_level = true;
            }
        }
        var get_second_level = false;
        if (self.first_level_pos >= second_level_index) {
            if (self.second_level == null) {
                self.second_level = try self.fs.alloc.alloc_array(u32,
                    self.fs.block_size / @sizeOf(u32));
                get_second_level = true;
            }
            if (self.second_level_pos >= self.fs.max_entries_per_block) {
                self.first_level_pos += 1;
                self.second_level_pos = 0;
                get_second_level = true;
            }
        }

        // Are We Done?
        if (self.first_level_pos > fourth_level_index) return 0;

        // Get New Levels if Needed and Bail if They're Not There
        if (get_second_level) {
            const get = self.inode.blocks[self.first_level_pos];
            if (get == 0) return 0;
            self.fs.get_entry_block(self.second_level.?, get);
        }
        if (get_third_level) {
            const get = self.second_level.?[self.second_level_pos];
            if (get == 0) return 0;
            self.fs.get_entry_block(self.third_level.?, get);
        }
        if (get_fourth_level) {
            const get = self.third_level.?[self.third_level_pos];
            if (get == 0) return 0;
            self.fs.get_entry_block(self.fourth_level.?, get);
        }

        // Return The Block Index
        if (self.first_level_pos == second_level_index) {
            return self.second_level.?[self.second_level_pos];
        }
        if (self.first_level_pos == third_level_index) {
            return self.third_level.?[self.third_level_pos];
        }
        if (self.first_level_pos == fourth_level_index) {
            return self.fourth_level.?[self.fourth_level_pos];
        }
        unreachable;
    }

    pub fn next(self: *DataBlockIterator) MemoryError!?[]u8 {
        // if (self.blocks_left == 0) return null;
        const block_index = try self.get_next_block_index();
        if (block_index == 0) return null;
        if (self.data_block == null) {
            self.data_block = try self.fs.alloc.alloc_array(u8, self.fs.block_size);
        }
        self.fs.get_data_block(self.data_block.?, block_index);
        return self.data_block;
    }

    pub fn done(self: *DataBlockIterator) void {
        if (self.data_block) self.fs.alloc.free_array(u8, self.data_block);
        if (self.second_level) self.fs.alloc.free_array(u32, self.second_level);
        if (self.third_level) self.fs.alloc.free_array(u32, self.third_level);
        if (self.fourth_level) self.fs.alloc.free_array(u32, self.fourth_level);
    }
};

const DirectoryEntry = packed struct {
    inode: u32,
    next_entry_offset: u16,
    name_size: u8,
    file_type: u8,
};

pub const Ext2 = struct {
    alloc: *Allocator = undefined,
    superblock: Superblock = Superblock{},
    block_size: usize = 0,
    max_entries_per_block: usize = 0,

    const root_inode_number = usize(2);

    pub fn get_block_group_descriptor(self: *Ext2,
            index: usize, dest: *BlockGroupDescriptor) void {
        const address = util.Ki(2) + @sizeOf(BlockGroupDescriptor) * index;
        if (read_from_drive(address, util.to_bytes(dest)) != @sizeOf(BlockGroupDescriptor)) {
            @panic("Could not read block group descriptor!");
        }
    }

    pub fn get_inode(self: *Ext2, n: usize, inode: *Inode) void {
        var block_group: BlockGroupDescriptor = undefined;
        self.get_block_group_descriptor((n - 1) / self.superblock.inodes_per_group, &block_group);
        const address = u64(block_group.inode_table) * self.block_size +
            ((n - 1) % self.superblock.inodes_per_group) * @sizeOf(Inode);
        if (read_from_drive(address, util.to_bytes(inode)) != @sizeOf(Inode)) {
            @panic("Could not read Inode!");
        }
        print.format("inode {}\n{}\n", n, inode.*);
    }

    pub fn get_data_block(self: *Ext2, block: []u8, index: usize) void {
        _ = read_from_drive(index * self.block_size, block);
    }

    pub fn get_entry_block(self: *Ext2, block: []u32, index: usize) void {
        self.get_data_block(@ptrCast([*]u8, block.ptr)[0..block.len * @sizeOf(u32)], index);
    }

    pub fn initialize(self: *Ext2, alloc: *Allocator) MemoryError!void {
        self.alloc = alloc;

        if (read_from_drive(util.Ki(1),
                util.to_bytes(&self.superblock)) != @sizeOf(Superblock)) {
            @panic("Could not read Ext2 Superblock!");
        }

        // print.format("{}\n", self.superblock);
        self.superblock.verify();

        self.block_size = self.superblock.block_size();
        self.max_entries_per_block = self.block_size / @sizeOf(u32);

        var i: usize = 0;
        var block_group: BlockGroupDescriptor = undefined;
        const block_group_count = self.superblock.block_group_count();
        // print.format("block_group_count: {}\n", block_group_count);
        while (i < block_group_count) {
            self.get_block_group_descriptor(i, &block_group);
            // print.format("Block Group Index {}\n{}\n", i, block_group);
            i += 1;
        }

        var root_inode: Inode = undefined;
        self.get_inode(root_inode_number, &root_inode);
        var block: [1024]u8 = undefined;
        // TODO: Directory Entry Iterator
        var block_array_index: usize = 0;
        while (block_array_index < 12) {
            const inode_number = root_inode.blocks[block_array_index];
            if (inode_number == 0) break;
            block_array_index  += 1;
            _ = read_from_drive(inode_number * self.block_size, block[0..]);
            var pos: usize = 0;
            while (pos < 1024) {
                const entry = @ptrCast(*DirectoryEntry, &block[pos]);
                const name_pos = pos + @sizeOf(DirectoryEntry);
                const name = block[name_pos..name_pos + entry.name_size];
                // print.format("{}\n", name);
                print.format("{}\n{}\n", name, entry.*);
                var entry_inode: Inode = undefined;
                self.get_inode(entry.inode, &entry_inode);

                var iter = DataBlockIterator{.fs = self, .inode = &entry_inode};
                while (true) {
                    const data_block = try iter.next();
                    if (data_block == null) break;
                    print.data_bytes(data_block.?);
                }

                pos += entry.next_entry_offset;
            }
        }
    }
};
