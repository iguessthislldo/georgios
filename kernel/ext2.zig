// Second Extended File System (Ext2)
//
// For Reference See:
//   https://en.wikipedia.org/wiki/Ext2
//   https://wiki.osdev.org/Ext2
//   https://www.nongnu.org/ext2-doc/ext2.html

const utils = @import("utils");
const georgios = @import("georgios");

const kernel = @import("kernel.zig");
const print = @import("print.zig");
const Allocator = @import("memory.zig").Allocator;
const MemoryError = @import("memory.zig").MemoryError;
const io = @import("io.zig");
const fs = @import("fs.zig");

pub const Error = fs.Error || io.BlockError || MemoryError || utils.Error;

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
    // Rest has been left out for now

    pub fn verify(self: *const Superblock) Error!void {
        if (self.magic != expected_magic) {
            print.string("Invalid Ext2 Magic\n");
            return Error.InvalidFilesystem;
        }
        if (self.major_revision != 1) {
            print.string("Invalid Ext2 Revision");
            return Error.InvalidFilesystem;
        }
        if ((utils.align_up(self.inode_count, self.inodes_per_group) / self.inodes_per_group)
                != self.block_group_count()) {
            print.string("Inconsistent Ext2 Block Group Count");
            return Error.InvalidFilesystem;
        }
    }

    pub fn block_size(self: *const Superblock) usize {
        // TODO: Zig Bug? Can't inline utils.Ki(1)
        return @as(usize, 1024) << @truncate(utils.UsizeLog2Type, self.log_block_size);
    }

    pub fn block_group_count(self: *const Superblock) usize {
        return utils.align_up(self.block_count, self.blocks_per_group) / self.blocks_per_group;
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

    ext2: *Ext2,
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
        } else if (block >= Ext2.second_level_start and block < self.ext2.third_level_start) {
            self.first_level_pos = second_level_index;
            self.second_level_pos = block - Ext2.second_level_start;
            self.third_level_pos = 0;
            self.fourth_level_pos = 0;
        } else if (block >= self.ext2.third_level_start and
                block < self.ext2.fourth_level_start) {
            self.first_level_pos = third_level_index;
            const level_offset = block - self.ext2.third_level_start;
            self.second_level_pos = level_offset / self.ext2.max_entries_per_block;
            self.third_level_pos = level_offset % self.ext2.max_entries_per_block;
            self.fourth_level_pos = 0;
        } else if (block >= self.ext2.fourth_level_start and
                block < self.ext2.max_fourth_level_entries) {
            self.first_level_pos = fourth_level_index;
            const level_offset = block - self.ext2.fourth_level_start;
            self.second_level_pos = level_offset / self.ext2.max_third_level_entries;
            const sub_level_offset = level_offset % self.ext2.max_third_level_entries;
            self.third_level_pos = sub_level_offset / self.ext2.max_entries_per_block;
            self.fourth_level_pos = sub_level_offset % self.ext2.max_entries_per_block;
        } else return Error.OutOfBounds;
        self.got = block * self.ext2.block_size;
        self.new_pos = true;
    }

    fn get_level(self: *DataBlockIterator, level: *?[]u32, index: u32) Error!void {
        if (level.* == null) {
            level.* = try self.ext2.alloc.alloc_array(
                u32, self.ext2.block_size / @sizeOf(u32));
        }
        try self.ext2.get_entry_block(level.*.?, index);
    }

    fn prepare_level(self: *DataBlockIterator, index: usize,
            level_pos: *usize, level: *?[]u32, parent_level_pos: *usize) bool {
        if (self.first_level_pos < index) return false;
        if (level_pos.* >= self.ext2.max_entries_per_block) {
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
                return DataBlockInfo.FillInZeros;
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
        if (self.first_level_pos > fourth_level_index) return DataBlockInfo.EndOfFile;

        // Get New Levels if Needed
        if (get_second_level) {
            const index = self.inode.blocks[self.first_level_pos];
            if (index == 0) {
                self.second_level_pos += 1;
                return DataBlockInfo.FillInZeros;
            }
            try self.get_level(&self.second_level, index);
        }
        if (get_third_level) {
            const index = self.second_level.?[self.second_level_pos];
            if (index == 0) {
                self.third_level_pos += 1;
                return DataBlockInfo.FillInZeros;
            }
            try self.get_level(&self.third_level, index);
        }
        if (get_fourth_level) {
            const index = self.third_level.?[self.third_level_pos];
            if (index == 0) {
                self.fourth_level_pos += 1;
                return DataBlockInfo.FillInZeros;
            }
            try self.get_level(&self.fourth_level, index);
        }

        // Return The Result
        switch (self.first_level_pos) {
            second_level_index => {
                const index = self.second_level.?[self.second_level_pos];
                if (index == 0) {
                    self.second_level_pos += 1;
                    return DataBlockInfo.FillInZeros;
                }
                return DataBlockInfo{.Index = index};
            },
            third_level_index => {
                const index = self.third_level.?[self.third_level_pos];
                if (index == 0) {
                    self.third_level_pos += 1;
                    return DataBlockInfo.FillInZeros;
                }
                return DataBlockInfo{.Index = index};
            },
            fourth_level_index => {
                const index = self.fourth_level.?[self.fourth_level_pos];
                if (index == 0) {
                    self.fourth_level_pos += 1;
                    return DataBlockInfo.FillInZeros;
                }
                return DataBlockInfo{.Index = index};
            },
            else => unreachable,
        }
    }

    pub fn next(self: *DataBlockIterator, dest: []u8) Error!?[]u8 {
        if (dest.len < self.ext2.block_size) {
            return Error.NotEnoughDestination;
        }
        const dest_use = dest[0..self.ext2.block_size];
        switch (try self.get_next_block_info()) {
            .Index => |index| {
                try self.ext2.get_data_block(dest_use, index);
            },
            .FillInZeros => utils.memory_set(dest_use, 0),
            .EndOfFile => return null,
        }
        const got = utils.min(u32, self.inode.size - self.got, self.ext2.block_size);
        // print.format("DataBlockIterator.next: got: {} {}\n", self.inode.size, self.got);
        self.got += got;
        return dest_use[0..got];
    }

    pub fn done(self: *DataBlockIterator) Error!void {
        if (self.second_level != null) try self.ext2.alloc.free_array(self.second_level.?);
        if (self.third_level != null) try self.ext2.alloc.free_array(self.third_level.?);
        if (self.fourth_level != null) try self.ext2.alloc.free_array(self.fourth_level.?);
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
        name: []const u8,
        inode: Inode,
    };

    ext2: *Ext2,
    inode: *Inode,
    data_block_iter: DataBlockIterator,
    buffer: []u8,
    block_count: usize,
    buffer_pos: usize = 0,
    initial: bool = true,
    value: Value = undefined,

    pub fn new(ext2: *Ext2, inode: *Inode) fs.Error!DirectoryIterator {
        if (!inode.is_directory()) {
            return fs.Error.NotADirectory;
        }
        return DirectoryIterator{
            .ext2 = ext2,
            .inode = inode,
            .data_block_iter = DataBlockIterator{.ext2 = ext2, .inode = inode},
            .buffer = try ext2.alloc.alloc_array(u8, ext2.block_size),
            .block_count = inode.size / ext2.block_size,
        };
    }

    pub fn next(self: *DirectoryIterator) fs.Error!bool {
        const get_next_block = self.buffer_pos >= self.ext2.block_size;
        if (get_next_block) {
            self.buffer_pos = 0;
            self.block_count -= 1;
            if (self.block_count == 0) {
                return false;
            }
        }
        if (get_next_block or self.initial) {
            self.initial = false;
            const result = self.data_block_iter.next(self.buffer) catch
                return fs.Error.Internal;
            if (result == null) {
                return false;
            }
        }
        const entry = @ptrCast(*DirectoryEntry, &self.buffer[self.buffer_pos]);
        const name_pos = self.buffer_pos + @sizeOf(DirectoryEntry);
        self.buffer_pos += entry.next_entry_offset;
        self.value.inode_number = entry.inode;
        self.value.name = self.buffer[name_pos..name_pos + entry.name_size];
        self.ext2.get_inode(entry.inode, &self.value.inode) catch
            return fs.Error.Internal;
        return true;
    }

    pub fn done(self: *DirectoryIterator) Error!void {
        try self.data_block_iter.done();
        try self.ext2.alloc.free_array(self.buffer);
    }
};

pub const File = struct {
    const Self = @This();

    ext2: *Ext2 = undefined,
    inode: Inode = undefined,
    io_file: io.File = undefined,
    data_block_iter: DataBlockIterator = undefined,
    buffer: ?[]u8 = null,
    position: usize = 0,

    pub fn init(self: *File, ext2: *Ext2, inode: u32) Error!void {
        self.* = File{};
        self.ext2 = ext2;
        try ext2.get_inode(inode, &self.inode);
        self.data_block_iter = DataBlockIterator{.ext2 = ext2, .inode = &self.inode};
        self.io_file = io.File{
            .read_impl = Self.read,
            .write_impl = io.File.unsupported.write_impl,
            .seek_impl = Self.seek,
            .close_impl = io.File.nop.close_impl,
        };
    }

    pub fn close(self: *File) MemoryError!void {
        if (self.buffer) |buffer| {
            try self.ext2.alloc.free_array(buffer);
        }
    }

    pub fn read(file: *io.File, to: []u8) io.FileError!usize {
        const self = @fieldParentPtr(Self, "io_file", file);
        if (self.buffer == null) {
            self.buffer = try self.ext2.alloc.alloc_array(u8, self.ext2.block_size);
        }
        var got: usize = 0;
        while (got < to.len) {
            // TODO: See if buffer already has the data we need!!!
            self.data_block_iter.set_position(self.position / self.ext2.block_size)
                    catch |e| {
                print.format("ERROR: ext2.File.read: set_position: {}\n", .{@errorName(e)});
                return io.FileError.Internal;
            };
            const block = self.data_block_iter.next(self.buffer.?) catch |e| {
                print.format("ERROR: ext2.File.read: next: {}\n", .{@errorName(e)});
                return io.FileError.Internal;
            };
            if (block == null) break;
            const read_size = utils.memory_copy_truncate(
                to[got..], block.?[self.position % self.ext2.block_size..]);
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
            self.position, self.inode.size, null, offset, seek_type);
        return self.position;
    }
};

pub const Ext2 = struct {
    const root_inode_number = @as(usize, 2);
    const second_level_start = 12;

    initialized: bool = false,
    alloc: *Allocator = undefined,
    block_store: *io.BlockStore = undefined,
    offset: io.AddressType = 0,
    superblock: Superblock = Superblock{},
    block_size: usize = 0,
    block_group_descriptor_table: io.AddressType = 0,
    max_entries_per_block: usize = 0,
    max_third_level_entries: usize = 0,
    max_fourth_level_entries: usize = 0,
    third_level_start: usize = 0,
    fourth_level_start: usize = 0,

    fn get_block_address(self: *const Ext2, index: usize) io.AddressType {
        return self.offset + index * self.block_size;
    }

    pub fn get_block_group_descriptor(self: *Ext2,
            index: usize, dest: *BlockGroupDescriptor) Error!void {
        try self.block_store.read(
            self.block_group_descriptor_table + @sizeOf(BlockGroupDescriptor) * index,
            utils.to_bytes(dest));
    }

    pub fn get_inode(self: *Ext2, n: usize, inode: *Inode) Error!void {
        var block_group: BlockGroupDescriptor = undefined;
        const nm1 = n - 1;
        try self.get_block_group_descriptor(
            nm1 / self.superblock.inodes_per_group, &block_group);
        const address = @as(u64, block_group.inode_table) * self.block_size +
            (nm1 % self.superblock.inodes_per_group) * @sizeOf(Inode);
        try self.block_store.read(self.offset + address, utils.to_bytes(inode));
        // print.format("inode {}\n{}\n", n, inode.*);
    }

    pub fn get_data_block(self: *Ext2, block: []u8, index: usize) Error!void {
        try self.block_store.read(self.get_block_address(index), block);
    }

    pub fn get_entry_block(self: *Ext2, block: []u32, index: usize) Error!void {
        try self.get_data_block(
            @ptrCast([*]u8, block.ptr)[0..block.len * @sizeOf(u32)], index);
    }

    pub fn init(self: *Ext2, alloc: *Allocator, block_store: *io.BlockStore) Error!void {
        self.alloc = alloc;
        self.block_store = block_store;

        try block_store.read(self.offset + utils.Ki(1), utils.to_bytes(&self.superblock));

        // print.format("{}\n", self.superblock);
        try self.superblock.verify();

        self.block_size = self.superblock.block_size();
        self.max_entries_per_block = self.block_size / @sizeOf(u32);
        self.block_group_descriptor_table = self.get_block_address(
            if (self.block_size >= utils.Ki(2)) 1 else 2);
        self.third_level_start = second_level_start + self.max_entries_per_block;
        self.max_third_level_entries =
            self.max_entries_per_block * self.max_entries_per_block;
        self.fourth_level_start = self.third_level_start + self.max_third_level_entries;
        self.max_fourth_level_entries =
            self.max_third_level_entries * self.max_entries_per_block;

        self.initialized = true;
    }

    fn find_in_directory(
            self: *Ext2, dir_inode: *Inode, name: []const u8, inode: *Inode) Error!u32 {
        if (!dir_inode.is_directory()) {
            return fs.Error.NotADirectory;
        }

        var dir_iter = try DirectoryIterator.new(self, dir_inode);
        defer dir_iter.done() catch |e| @panic(@typeName(@TypeOf(e)));
        while (try dir_iter.next()) {
            if (utils.memory_compare(name, dir_iter.value.name)) {
                inode.* = dir_iter.value.inode;
                return dir_iter.value.inode_number;
            }
        }

        return fs.Error.FileNotFound;
    }

    const Resolved = struct {
        inode_number: u32 = undefined,
        path: ?*[]u8 = null,
        inode: ?*Inode = null,
    };

    fn resolve_path(self: *Ext2, path_str: []const u8, resolved: *Resolved) Error!void {
        // See man page path_resolution(7) for reference
        // TODO: Assert path with trailing slash is a directory

        // Get unresolved full path
        var path = fs.Path{.alloc = self.alloc};
        try path.init(path_str);
        defer (path.done() catch @panic("path.done()"));
        if (!path.absolute) {
            var cwd = kernel.threading_mgr.get_cwd_heap() catch return fs.Error.Internal;
            try path.prepend(cwd);
            try kernel.alloc.free_array(cwd);
        }

        // Get root node
        var inode: *Inode = resolved.inode orelse try self.alloc.alloc(Inode);
        defer {
            if (resolved.inode == null) {
                self.alloc.free(inode) catch @panic("self.alloc.free(inode)");
            }
        }
        resolved.inode_number = Ext2.root_inode_number;
        self.get_inode(resolved.inode_number, inode) catch return fs.Error.Internal;

        // Find inode and build resolved path
        var resolved_path = fs.Path{.alloc = self.alloc, .absolute = true};
        try resolved_path.init(null);
        defer (resolved_path.done() catch @panic("resolved_path.done()"));
        var it = path.list.const_iterator();
        while (it.next()) |component| {
            resolved.inode_number = try self.find_in_directory(inode, component, inode);
            if (utils.memory_compare(component, "..")) {
                try resolved_path.pop_component();
            } else {
                try resolved_path.push_component(component);
            }
        }

        if (resolved.path) |rp| {
            rp.* = try resolved_path.get();
        }
    }

    fn resolve_kind(self: *Ext2, path_str: []const u8, resolved: *Resolved,
            valid_fn: fn(inode: *const Inode) bool, invalid_error: Error) Error!void {
        const alloc_inode = resolved.inode == null;
        if (alloc_inode) {
            resolved.inode = try self.alloc.alloc(Inode);
        }
        defer {
            if (alloc_inode) {
                self.alloc.free(resolved.inode.?) catch @panic("self.alloc.free(inode)");
                resolved.inode = null;
            }
        }
        try self.resolve_path(path_str, resolved);
        if (!valid_fn(resolved.inode.?)) {
            return invalid_error;
        }
    }

    fn resolve_directory(self: *Ext2, path_str: []const u8, resolved: *Resolved) Error!void {
        try self.resolve_kind(path_str, resolved, Inode.is_directory, fs.Error.NotADirectory);
    }

    pub fn resolve_directory_path(self: *Ext2, path: []const u8) Error![]const u8 {
        var resolved_path: []u8 = undefined;
        var resolved = Resolved{.path = &resolved_path};
        try self.resolve_directory(path, &resolved);
        return resolved_path;
    }

    fn resolve_file(self: *Ext2, path_str: []const u8, resolved: *Resolved) Error!void {
        try self.resolve_kind(path_str, resolved, Inode.is_file, fs.Error.NotAFile);
    }

    pub fn open(self: *Ext2, path: []const u8) fs.Error!*File {
        if (!self.initialized) return fs.Error.InvalidFilesystem;
        // print.format("open({})\n", .{path});

        var resolved = Resolved{};
        try self.resolve_file(path, &resolved);

        const file = try self.alloc.alloc(File);
        file.init(self, resolved.inode_number) catch return fs.Error.Internal;

        return file;
    }

    pub fn close(self: *Ext2, file: *File) io.FileError!void {
        if (!self.initialized) return io.FileError.InvalidFileId;
        try file.close();
        try self.alloc.free(file);
    }

    fn open_dir(self: *Ext2, path: []const u8) fs.Error!DirectoryIterator.Value {
        var inode = try self.alloc.alloc(Inode);
        defer self.alloc.free(inode) catch @panic("self.alloc.free(inode)");
        var resolved = Resolved{.inode = inode};
        try self.resolve_directory(path, &resolved);

        return DirectoryIterator.Value{
            .inode_number = resolved.inode_number,
            .name = "",
            .inode = resolved.inode.?.*,
        };
    }

    pub fn next_dir_entry(self: *Ext2, dir_entry: *georgios.DirEntry) Error!void {
        if (!self.initialized) return fs.Error.InvalidFilesystem;

        var in_dir: DirectoryIterator.Value = undefined;
        if (dir_entry.dir_inode) |dir_inode| {
            try self.get_inode(dir_inode, &in_dir.inode);
            // Note: Leaving in_dir.inode_number undefined
        } else {
            in_dir = try self.open_dir(dir_entry.dir);
            dir_entry.dir_inode = in_dir.inode_number;
        }

        var dir_iter = try DirectoryIterator.new(self, &in_dir.inode);
        defer dir_iter.done() catch |e| @panic(@typeName(@TypeOf(e)));
        var get_next = false;
        while (try dir_iter.next()) {
            // print.format("dir_item: {} {}\n", .{dir_iter.value.inode_number, dir_iter.value.name});
            var return_this = false;
            if (get_next) {
                if (dir_entry.current_entry_inode) |current| {
                    // Case of listing / where . == ..
                    // TODO: Also maybe if there are two or more hard links to
                    // the same file in a row. This might be have be rethought
                    // out though because it will get in a loop if identical
                    // hard links are interspersed in the directory listing.
                    if (current == dir_iter.value.inode_number) {
                        continue;
                    }
                }
                // print.format("get_next return this\n", .{});
                return_this = true;
            } else if (dir_entry.current_entry_inode) |current| {
                // print.format("current: {}\n", .{current});
                if (current == dir_iter.value.inode_number) {
                    get_next = true;
                    continue;
                }
            } else {
                // print.format("return this\n", .{});
                return_this = true;
            }
            if (return_this) {
                dir_entry.current_entry_inode = dir_iter.value.inode_number;
                const len = utils.memory_copy_truncate(
                    dir_entry.current_entry_buffer[0..], dir_iter.value.name);
                dir_entry.current_entry = dir_entry.current_entry_buffer[0..len];
                return;
            }
        }

        // print.format("done\n", .{});

        dir_entry.current_entry.len = 0;
        dir_entry.current_entry_inode = null;
        dir_entry.done = true;
    }
};
