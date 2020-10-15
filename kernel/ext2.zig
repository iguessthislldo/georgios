// Second Extended File System (Ext2)
//
// For Reference See:
//   https://en.wikipedia.org/wiki/Ext2
//   https://wiki.osdev.org/Ext2
//   https://www.nongnu.org/ext2-doc/ext2.html

const util = @import("util.zig");
const print = @import("print.zig");
const Allocator = @import("memory.zig").Allocator;
const MemoryError = @import("memory.zig").MemoryError;
const io = @import("io.zig");

const Error = error {
    FileNotFound,
    InvalidFilesystem,
} || io.BlockError || MemoryError || util.Error;

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

    pub fn verify(self: *const Superblock) Error!void {
        if (self.magic != expected_magic) {
            print.string("Invalid Ext2 Magic\n");
            return Error.InvalidFilesystem;
        }
        if (self.major_revision != 1) {
            print.string("Invalid Ext2 Revision");
            return Error.InvalidFilesystem;
        }
        if ((util.align_up(self.inode_count, self.inodes_per_group) / self.inodes_per_group)
                != self.block_group_count()) {
            print.string("Inconsistent Ext2 Block Group Count");
            return Error.InvalidFilesystem;
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

    pub fn is_file(self: *const Inode) bool {
        return self.mode & 0x8000 > 0;
    }

    pub fn is_directory(self: *const Inode) bool {
        return self.mode & 0x4000 > 0;
    }
};

pub const DataBlockIterator = struct {
    const max_first_level_index: u8 = 11;
    const second_level_index = max_first_level_index + 1;
    const third_level_index = second_level_index + 1;
    const fourth_level_index = third_level_index + 1;

    const DataBlockInfoState = enum {
        Index,
        FillInZeros,
        EndOfFile,
    };
    const DataBlockInfo = union(DataBlockInfoState) {
        Index: u32,
        FillInZeros: void,
        EndOfFile: void,
    };

    fs: *Ext2,
    inode: *Inode,
    got: usize = 0,
    first_level_pos: usize = 0,
    second_level: ?[]u32 = null,
    second_level_pos: usize = 0,
    third_level: ?[]u32 = null,
    third_level_pos: usize = 0,
    fourth_level: ?[]u32 = null,
    fourth_level_pos: usize = 0,
    new_pos: bool = false,

    pub fn set_position(self: *DataBlockIterator, block: usize) Error!void {
        if (block <= max_first_level_index) {
            self.first_level_pos = block;
            self.second_level_pos = 0;
            self.third_level_pos = 0;
            self.fourth_level_pos = 0;
        } else if (block >= Ext2.second_level_start and block < self.fs.third_level_start) {
            self.first_level_pos = second_level_index;
            self.second_level_pos = block - Ext2.second_level_start;
            self.third_level_pos = 0;
            self.fourth_level_pos = 0;
        } else if (block >= self.fs.third_level_start and block < self.fs.fourth_level_start) {
            self.first_level_pos = third_level_index;
            const level_offset = block - self.fs.third_level_start;
            self.second_level_pos = level_offset / self.fs.max_entries_per_block;
            self.third_level_pos = level_offset % self.fs.max_entries_per_block;
            self.fourth_level_pos = 0;
        } else if (block >= self.fs.fourth_level_start and
                block < self.fs.max_fourth_level_entries) {
            self.first_level_pos = fourth_level_index;
            const level_offset = block - self.fs.fourth_level_start;
            self.second_level_pos = level_offset / self.fs.max_third_level_entries;
            const sub_level_offset = level_offset % self.fs.max_third_level_entries;
            self.third_level_pos = sub_level_offset / self.fs.max_entries_per_block;
            self.fourth_level_pos = sub_level_offset % self.fs.max_entries_per_block;
        } else return Error.OutOfBounds;
        self.got = block * self.fs.block_size;
        self.new_pos = true;
    }

    fn get_level(self: *DataBlockIterator, level: *?[]u32, index: u32) Error!void {
        if (level.* == null) {
            level.* = try self.fs.alloc.alloc_array(u32, self.fs.block_size / @sizeOf(u32));
        }
        try self.fs.get_entry_block(level.*.?, index);
    }

    fn prepare_level(self: *DataBlockIterator, index: usize,
            level_pos: *usize, level: *?[]u32, parent_level_pos: *usize) bool {
        if (self.first_level_pos < index) return false;
        if (level_pos.* >= self.fs.max_entries_per_block) {
            parent_level_pos.* += 1;
            level_pos.* = 0;
            return true;
        }
        return level.* == null or self.new_pos;
    }

    fn get_next_block_info(self: *DataBlockIterator) Error!DataBlockInfo {
        // print.format("get_next_block_index_i: {}\n", self.first_level_pos);
        // First Level
        if (self.first_level_pos <= max_first_level_index) {
            const index = self.inode.blocks[self.first_level_pos];
            self.first_level_pos += 1;
            if (index == 0) {
                return DataBlockInfo(.FillInZeros);
            }
            return DataBlockInfo{.Index = index};
        }

        // Figure Out Our Position
        var get_fourth_level = self.prepare_level(
            fourth_level_index, &self.fourth_level_pos, &self.fourth_level,
            &self.third_level_pos);
        var get_third_level = self.prepare_level(
            third_level_index, &self.third_level_pos, &self.third_level,
            &self.second_level_pos);
        var get_second_level = self.prepare_level(
            second_level_index, &self.second_level_pos, &self.second_level,
            &self.first_level_pos);
        if (self.new_pos) self.new_pos = false;

        // Check for end of blocks
        if (self.first_level_pos > fourth_level_index) return DataBlockInfo(.EndOfFile);

        // Get New Levels if Needed
        if (get_second_level) {
            const index = self.inode.blocks[self.first_level_pos];
            if (index == 0) {
                self.second_level_pos += 1;
                return DataBlockInfo(.FillInZeros);
            }
            try self.get_level(&self.second_level, index);
        }
        if (get_third_level) {
            const index = self.second_level.?[self.second_level_pos];
            if (index == 0) {
                self.third_level_pos += 1;
                return DataBlockInfo(.FillInZeros);
            }
            try self.get_level(&self.third_level, index);
        }
        if (get_fourth_level) {
            const index = self.third_level.?[self.third_level_pos];
            if (index == 0) {
                self.fourth_level_pos += 1;
                return DataBlockInfo(.FillInZeros);
            }
            try self.get_level(&self.fourth_level, index);
        }

        // Return The Result
        switch (self.first_level_pos) {
            second_level_index => {
                const index = self.second_level.?[self.second_level_pos];
                if (index == 0) {
                    self.second_level_pos += 1;
                    return DataBlockInfo(.FillInZeros);
                }
                return DataBlockInfo{.Index = index};
            },
            third_level_index => {
                const index = self.third_level.?[self.third_level_pos];
                if (index == 0) {
                    self.third_level_pos += 1;
                    return DataBlockInfo(.FillInZeros);
                }
                return DataBlockInfo{.Index = index};
            },
            fourth_level_index => {
                const index = self.fourth_level.?[self.fourth_level_pos];
                if (index == 0) {
                    self.fourth_level_pos += 1;
                    return DataBlockInfo(.FillInZeros);
                }
                return DataBlockInfo{.Index = index};
            },
            else => unreachable,
        }
    }

    pub fn next(self: *DataBlockIterator, dest: []u8) Error!?[]u8 {
        if (dest.len < self.fs.block_size) {
            return Error.NotEnoughDestination;
        }
        const dest_use = dest[0..self.fs.block_size];
        switch (try self.get_next_block_info()) {
            .Index => |index| {
                try self.fs.get_data_block(dest_use, index);
            },
            .FillInZeros => util.memory_set(dest_use, 0),
            .EndOfFile => return null,
        }
        const got = util.min(u32, self.inode.size - self.got, self.fs.block_size);
        // print.format("DataBlockIterator.next: got: {} {}\n", self.inode.size, self.got);
        self.got += got;
        return dest_use[0..got];
    }

    pub fn done(self: *DataBlockIterator) Error!void {
        if (self.second_level != null) try self.fs.alloc.free_array(self.second_level.?);
        if (self.third_level != null) try self.fs.alloc.free_array(self.third_level.?);
        if (self.fourth_level != null) try self.fs.alloc.free_array(self.fourth_level.?);
    }
};

const DirectoryEntry = packed struct {
    inode: u32,
    next_entry_offset: u16,
    name_size: u8,
    file_type: u8,
    // NOTE: This field seems to always be 0 for the disk I am creating at the
    // time of writing, so this field can't be relied on.
};

const DirectoryIterator = struct {
    pub const Value = struct {
        inode_number: u32,
        name: []u8,
        inode: Inode,
    };

    fs: *Ext2,
    inode: *Inode,
    data_block_iter: DataBlockIterator,
    buffer: []u8,
    block_count: usize,
    buffer_pos: usize = 0,
    initial: bool = true,
    value: Value = undefined,

    pub fn new(fs: *Ext2, inode: *Inode) Error!DirectoryIterator {
        return DirectoryIterator{
            .fs = fs,
            .inode = inode,
            .data_block_iter = DataBlockIterator{.fs = fs, .inode = inode},
            .buffer = try fs.alloc.alloc_array(u8, fs.block_size),
            .block_count = inode.size / fs.block_size,
        };
    }

    pub fn next(self: *DirectoryIterator) Error!bool {
        const get_next_block = self.buffer_pos >= self.fs.block_size;
        if (get_next_block) {
            self.buffer_pos = 0;
            self.block_count -= 1;
            if (self.block_count == 0) {
                return false;
            }
        }
        if (get_next_block or self.initial) {
            self.initial = false;
            // Zig Bug? Should try have higher precedence in order of
            // operations? (at least more than ==)
            if ((try self.data_block_iter.next(self.buffer)) == null) {
                return false;
            }
        }
        const entry = @ptrCast(*DirectoryEntry, &self.buffer[self.buffer_pos]);
        const name_pos = self.buffer_pos + @sizeOf(DirectoryEntry);
        self.buffer_pos += entry.next_entry_offset;
        self.value.inode_number = entry.inode;
        self.value.name = self.buffer[name_pos..name_pos + entry.name_size];
        try self.fs.get_inode(entry.inode, &self.value.inode);
        return true;
    }

    pub fn done(self: *DirectoryIterator) Error!void {
        try self.data_block_iter.done();
        try self.fs.alloc.free_array(self.buffer);
    }
};

pub const File = struct {
    const Self = @This();

    const FileError = Error || io.FileError;

    fs: *Ext2 = undefined,
    inode: Inode = undefined,
    io_file: io.File = undefined,
    data_block_iter: DataBlockIterator = undefined,
    buffer: ?[]u8 = null,
    position: usize = 0,

    pub fn initialize(self: *File, fs: *Ext2, inode: u32) Error!void {
        self.* = File{};
        self.fs = fs;
        try fs.get_inode(inode, &self.inode);
        self.data_block_iter = DataBlockIterator{.fs = fs, .inode = &self.inode};
        self.io_file = io.File{
            .read_impl = Self.read,
            .write_impl = io.File.unsupported.write_impl,
            .seek_impl = Self.seek,
            .close_impl = io.File.nop.close_impl,
        };
    }

    pub fn read(file: *io.File, to: []u8) FileError!usize {
        const self = @fieldParentPtr(Self, "io_file", file);
        if (self.buffer == null) {
            self.buffer = try self.fs.alloc.alloc_array(u8, self.fs.block_size);
        }
        var got: usize = 0;
        while (got < to.len) {
            // TODO: See if buffer already has the data we need!!!
            try self.data_block_iter.set_position(self.position / self.fs.block_size);
            const block = try self.data_block_iter.next(self.buffer.?);
            if (block == null) break;
            const read_size = util.memory_copy_truncate(
                to[got..], block.?[self.position % self.fs.block_size..]);
            if (read_size == 0) break;
            self.position += read_size;
            got += read_size;
        }
        return got;
    }

    pub fn seek(file: *io.File,
            offset: isize, seek_type: io.File.SeekType) io.FileError!usize {
        const self = @fieldParentPtr(Self, "io_file", file);
        self.position = try io.File.generic_seek(
            self.position, self.inode.size, false, offset, seek_type);
        return self.position;
    }
};

pub const Ext2 = struct {
    const root_inode_number = usize(2);
    const second_level_start = 12;

    initialized: bool = false,
    alloc: *Allocator = undefined,
    block_store: *io.BlockStore = undefined,
    superblock: Superblock = Superblock{},
    block_size: usize = 0,
    max_entries_per_block: usize = 0,
    max_third_level_entries: usize = 0,
    max_fourth_level_entries: usize = 0,
    third_level_start: usize = 0,
    fourth_level_start: usize = 0,

    pub fn get_block_group_descriptor(self: *Ext2,
            index: usize, dest: *BlockGroupDescriptor) Error!void {
        const address = util.Ki(2) + @sizeOf(BlockGroupDescriptor) * index;
        try self.block_store.read(address, util.to_bytes(dest));
    }

    pub fn get_inode(self: *Ext2, n: usize, inode: *Inode) Error!void {
        var block_group: BlockGroupDescriptor = undefined;
        const nm1 = n - 1;
        try self.get_block_group_descriptor(
            nm1 / self.superblock.inodes_per_group, &block_group);
        const address = u64(block_group.inode_table) * self.block_size +
            (nm1 % self.superblock.inodes_per_group) * @sizeOf(Inode);
        try self.block_store.read(address, util.to_bytes(inode));
        // print.format("inode {}\n{}\n", n, inode.*);
    }

    pub fn get_data_block(self: *Ext2, block: []u8, index: usize) Error!void {
        try self.block_store.read(index * self.block_size, block);
    }

    pub fn get_entry_block(self: *Ext2, block: []u32, index: usize) Error!void {
        try self.get_data_block(
            @ptrCast([*]u8, block.ptr)[0..block.len * @sizeOf(u32)], index);
    }

    pub fn initialize(self: *Ext2, alloc: *Allocator, block_store: *io.BlockStore) Error!void {
        self.alloc = alloc;
        self.block_store = block_store;

        try block_store.read(util.Ki(1), util.to_bytes(&self.superblock));

        // print.format("{}\n", self.superblock);
        try self.superblock.verify();

        self.block_size = self.superblock.block_size();
        self.max_entries_per_block = self.block_size / @sizeOf(u32);
        self.third_level_start = second_level_start + self.max_entries_per_block;
        self.max_third_level_entries =
            self.max_entries_per_block * self.max_entries_per_block;
        self.fourth_level_start = self.third_level_start + self.max_third_level_entries;
        self.max_fourth_level_entries =
            self.max_third_level_entries * self.max_entries_per_block;

        self.initialized = true;
    }

    pub fn open(self: *Ext2, name: []const u8) Error!*File {
        if (!self.initialized) return Error.InvalidFilesystem;
        var root_inode: Inode = undefined;
        try self.get_inode(root_inode_number, &root_inode);
        var dir_iter = try DirectoryIterator.new(self, &root_inode);
        defer dir_iter.done() catch |e| @panic(@typeName(@typeOf(e)));
        while (try dir_iter.next()) {
            // print.format("entry: {}\n", dir_iter.value);
            if (dir_iter.value.inode.is_file() and
                    util.memory_compare(name, dir_iter.value.name)) {
                const file = try self.alloc.alloc(File);
                try file.initialize(self, dir_iter.value.inode_number);
                return file;
            }
        }
        return Error.FileNotFound;
    }
};
