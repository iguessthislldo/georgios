// Second Extended File System (Ext2)
//
// One of the longest lived incarnation of Linux's native file system.
//
// For Refernce See:
//   https://www.nongnu.org/ext2-doc/ext2.html
//   https://wiki.osdev.org/Ext2

const util = @import("util.zig");
const print = @import("print.zig");

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

const DirectoryEntry = packed struct {
    inode: u32,
    next_entry_offset: u16,
    name_size: u8,
    file_type: u8,
};

pub const Ext2 = struct {
    superblock: Superblock = Superblock{},
    block_size: usize = 0,

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

    pub fn initialize(self: *Ext2) void {
        if (read_from_drive(util.Ki(1),
                util.to_bytes(&self.superblock)) != @sizeOf(Superblock)) {
            @panic("Could not read Ext2 Superblock!");
        }

        print.format("{}\n", self.superblock);
        self.superblock.verify();

        self.block_size = self.superblock.block_size();

        var i: usize = 0;
        var block_group: BlockGroupDescriptor = undefined;
        const block_group_count = self.superblock.block_group_count();
        print.format("block_group_count: {}\n", block_group_count);
        while (i < block_group_count) {
            self.get_block_group_descriptor(i, &block_group);
            print.format("Block Group Index {}\n{}\n", i, block_group);
            i += 1;
        }

        var root_inode: Inode = undefined;
        self.get_inode(root_inode_number, &root_inode);
        var block: [1024]u8 = undefined;
        _ = read_from_drive(root_inode.blocks[0] * self.block_size, block[0..]);
        var pos: usize = 0;
        while (pos < 1024) {
            const entry = @ptrCast(*DirectoryEntry, &block[pos]);
            const name_pos = pos + @sizeOf(DirectoryEntry);
            const name = block[name_pos..name_pos + entry.name_size];
            print.format("{}\n{}\n", name, entry.*);
            pos += entry.next_entry_offset;
        }
    }
};
