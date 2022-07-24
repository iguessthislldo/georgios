// Second Extended File System (Ext2)
//
// For Reference See:
//   https://en.wikipedia.org/wiki/Ext2
//   https://wiki.osdev.org/Ext2
//   https://www.nongnu.org/ext2-doc/ext2.html

const std = @import("std");

const utils = @import("utils");
const georgios = @import("georgios");

const kernel = @import("../kernel.zig");
const print = @import("../print.zig");
const Allocator = @import("../memory.zig").Allocator;
const MemoryError = @import("../memory.zig").MemoryError;
const io = @import("../io.zig");
const fs = @import("../fs.zig");
const Vnode = fs.Vnode;
const Vfilesystem = fs.Vfilesystem;
const DirIterator = fs.DirIterator;
const Error = fs.Error;

const Ext2 = @This();

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

    fn verify(self: *const Superblock) Error!void {
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
        // TODO: Verify things related to inode_size
    }

    fn block_size(self: *const Superblock) usize {
        // TODO: Zig Bug? Can't inline utils.Ki(1)
        return @as(usize, 1024) << @truncate(utils.UsizeLog2Type, self.log_block_size);
    }

    fn block_group_count(self: *const Superblock) usize {
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
    // TODO: Revert when https://github.com/ziglang/zig/issues/2627 is fixed
    // blocks: [15]u32,
    // generation: u32,
    blocks: [16]u32,
    file_acl: u32,
    dir_acl: u32,
    fragment_address: u32,
    os_dependant_field_2: [12]u8,

    fn is_file(self: *const Inode) bool {
        return self.mode & 0x8000 > 0;
    }

    fn is_directory(self: *const Inode) bool {
        return self.mode & 0x4000 > 0;
    }
};

const DataBlockIterator = struct {
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

    fn set_position(self: *DataBlockIterator, block: usize) Error!void {
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

    fn next(self: *DataBlockIterator, dest: []u8) Error!?[]u8 {
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
        const got = @minimum(@as(usize, self.inode.size) - self.got, self.ext2.block_size);
        // std.debug.print("DataBlockIterator.next: got: {} {} {}\n", .{self.inode.size, self.got, self.ext2.block_size});
        self.got += got;
        return dest_use[0..got];
    }

    fn done(self: *DataBlockIterator) Error!void {
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

const DirIteratorImpl = struct {
    ext2: *Ext2,
    node: *Node,
    alloc: *Allocator,
    dir_iter: DirIterator,
    data_block_iter: DataBlockIterator,
    buffer: []u8,
    block_count: usize,
    buffer_pos: usize = 0,
    initial: bool = true,
    fn new(vnode: *Vnode) Error!*DirIterator {
        const node = @fieldParentPtr(Node, "vnode", vnode);
        const ext2 = node.ext2;
        const inode = &node.inode;
        var impl = try ext2.alloc.alloc(DirIteratorImpl);
        impl.* = .{
            .alloc = ext2.alloc,
            .ext2 = ext2,
            .node = node,
            .data_block_iter = DataBlockIterator{.ext2 = ext2, .inode = inode},
            .buffer = try ext2.alloc.alloc_array(u8, ext2.block_size),
            .block_count = inode.size / ext2.block_size,
            .dir_iter = .{.dir = &node.vnode, .next_impl = next_impl, .done_impl = done_impl},
        };
        return &impl.dir_iter;
    }

    fn next_impl(dir_it: *DirIterator) Error!?DirIterator.Result {
        const self = @fieldParentPtr(DirIteratorImpl, "dir_iter", dir_it);

        const get_next_block = self.buffer_pos >= self.ext2.block_size;
        if (get_next_block) {
            self.buffer_pos = 0;
            self.block_count -= 1;
            if (self.block_count == 0) {
                return null;
            }
        }
        if (get_next_block or self.initial) {
            self.initial = false;
            const result = self.data_block_iter.next(self.buffer) catch
                return Error.Internal;
            if (result == null) {
                return null;
            }
        }
        const entry = @ptrCast(*DirectoryEntry, &self.buffer[self.buffer_pos]);
        const name_pos = self.buffer_pos + @sizeOf(DirectoryEntry);
        self.buffer_pos += entry.next_entry_offset;

        return DirIterator.Result{
            .name = self.buffer[name_pos..name_pos + entry.name_size],
            .node = &(try self.ext2.get_node(entry.inode)).vnode,
        };
    }

    fn done_impl(dir_it: *DirIterator) void {
        const self = @fieldParentPtr(DirIteratorImpl, "dir_iter", dir_it);
        self.alloc.free(self.buffer) catch @panic("Ext2 DirIterator done");
        self.alloc.free(self) catch @panic("Ext2 DirIterator done");
    }
};

const Node = struct {
    ext2: *Ext2,
    vnode: Vnode,
    inode: Inode = undefined,
    io_file: io.File = undefined,

    data_block_iter: DataBlockIterator = undefined,
    buffer: ?[]u8 = null,
    position: usize = 0,

    fn init(self: *Node, ext2: *Ext2, kind: Vnode.Kind) void {
        self.* = .{
            .ext2 = ext2,
            .vnode = .{
                .fs = &ext2.vfs,
                .kind = kind,
                .get_dir_iter_impl = DirIteratorImpl.new,
                .create_node_impl = create_node_impl,
                .unlink_impl = unlink_impl,
                .get_io_file_impl = get_io_file_impl,
                .close_impl = close_impl,
            },
            .io_file = .{
                .read_impl = read,
                .write_impl = io.File.unsupported.write_impl,
                .seek_impl = seek,
                .close_impl = io.File.nop.close_impl,
            },
        };
    }

    fn init_after_inode(self: *Node) void {
        self.vnode.kind = .{
            .file = self.inode.is_file(),
            .directory = self.inode.is_directory(),
        };
        self.data_block_iter = DataBlockIterator{.ext2 = self.ext2, .inode = &self.inode};
    }

    fn done(self: *Node) Error!void {
        if (self.buffer) |buffer| {
            try self.ext2.alloc.free_array(buffer);
        }
    }

    fn create_node_impl(vnode: *Vnode, name: []const u8, kind: Vnode.Kind) Error!*Vnode {
        const self = @fieldParentPtr(Node, "vnode", vnode);
        _ = self;
        _ = name;
        _ = kind;
        return Error.Unsupported;
    }

    fn unlink_impl(vnode: *Vnode, name: []const u8) Error!void {
        const self = @fieldParentPtr(Node, "vnode", vnode);
        _ = self;
        _ = name;
        return Error.Unsupported;
    }

    fn get_io_file_impl(vnode: *Vnode) Error!*io.File {
        const self = @fieldParentPtr(Node, "vnode", vnode);
        return &self.io_file;
    }

    fn close_impl(vnode: *Vnode) Error!void {
        const self = @fieldParentPtr(Node, "vnode", vnode);
        self.position = 0;
    }

    fn read(file: *io.File, to: []u8) io.FileError!usize {
        const self = @fieldParentPtr(Node, "io_file", file);
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

    fn seek(file: *io.File,
            offset: isize, seek_type: io.File.SeekType) io.FileError!usize {
        const self = @fieldParentPtr(Node, "io_file", file);
        self.position = try io.File.generic_seek(
            self.position, self.inode.size, null, offset, seek_type);
        return self.position;
    }
};

const NodeCache = std.AutoHashMap(u32, *Node);

const root_inode_number = @as(usize, 2);
const second_level_start = 12;

vfs: fs.Vfilesystem = undefined,
node_cache: NodeCache = undefined,
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
    return self.offset + @as(u64, index) * @as(u64, self.block_size);
}

fn get_block_group_descriptor(self: *Ext2,
        index: usize, dest: *BlockGroupDescriptor) Error!void {
    try self.block_store.read(
        self.block_group_descriptor_table + @sizeOf(BlockGroupDescriptor) * index,
        utils.to_bytes(dest));
}

fn get_node(self: *Ext2, n: u32) Error!*Node {
    if (self.node_cache.get(n)) |node| {
        return node;
    }

    var node: *Node = try self.alloc.alloc(Node);
    node.init(self, undefined); // On purpose, wait until we got the inode
    errdefer self.alloc.free(node) catch unreachable;

    // Get Inode
    var block_group: BlockGroupDescriptor = undefined;
    const nm1 = n - 1;
    try self.get_block_group_descriptor(
        nm1 / self.superblock.inodes_per_group, &block_group);
    const address = @as(u64, block_group.inode_table) * self.block_size +
        (nm1 % self.superblock.inodes_per_group) * self.superblock.inode_size;
    try self.block_store.read(self.offset + address, utils.to_bytes(&node.inode));

    node.init_after_inode();
    try self.node_cache.put(n, node);

    return node;
}

fn get_data_block(self: *Ext2, block: []u8, index: usize) Error!void {
    try self.block_store.read(self.get_block_address(index), block);
}

fn get_entry_block(self: *Ext2, block: []u32, index: usize) Error!void {
    try self.get_data_block(
        @ptrCast([*]u8, block.ptr)[0..block.len * @sizeOf(u32)], index);
}

pub fn init(self: *Ext2, alloc: *Allocator, block_store: *io.BlockStore) Error!void {
    self.alloc = alloc;

    self.vfs = .{
        .get_root_vnode_impl = get_root_vnode_impl,
    };
    self.node_cache = NodeCache.init(alloc.std_allocator());

    self.block_store = block_store;

    try block_store.read(self.offset + utils.Ki(1), utils.to_bytes(&self.superblock));

    // std.debug.print("{}\n", .{self.superblock});
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

fn done(self: *Ext2) void {
    var it = self.node_cache.iterator();
    while (it.next()) |kv| {
        kv.value_ptr.*.done() catch unreachable;
        self.alloc.free(kv.value_ptr.*) catch unreachable;
    }
    self.node_cache.deinit();
}

fn get_root_vnode_impl(vfs: *Vfilesystem) Error!*Vnode {
    const self = @fieldParentPtr(Ext2, "vfs", vfs);
    return &(try self.get_node(2)).vnode;
}

const Ext2Test = struct {
    alloc: kernel.memory.UnitTestAllocator = .{},
    check_allocs: bool = false,
    file: std.fs.File = undefined,
    fbs: io.StdFileBlockStore = .{},
    ext2: Ext2 = .{},
    m: fs.Manager = undefined,

    fn init(self: *Ext2Test) !void {
        self.alloc.init();
        const alloc_if = &self.alloc.allocator;
        self.file = try std.fs.cwd().openFile(
            "misc/ext2-test-disk/ext2-test-disk.img", .{.read = true});
        self.fbs.init(alloc_if, &self.file, 1024);
        try self.ext2.init(alloc_if, &self.fbs.block_store_if);
        self.m.init(alloc_if, &self.ext2.vfs);
    }

    fn reached_end(self: *Ext2Test) void {
        self.check_allocs = true;
    }

    fn done(self: *Ext2Test) void {
        self.ext2.done();
        self.alloc.done_check_if(&self.check_allocs);
        self.file.close();
    }
};

fn test_reading(file: *io.File, comptime expected: []const u8) !void {
    var offset: usize = 0;
    var read_buffer: [expected.len]u8 = undefined;
    while (offset < expected.len) {
        try std.testing.expectEqual(offset, try file.seek(@intCast(isize, offset), .FromStart));
        try std.testing.expectEqual(expected.len - offset, try file.read(read_buffer[offset..]));
        try std.testing.expectEqualStrings(expected[offset..], read_buffer[offset..]);
        offset += 1;
    }
}

test "Ext2" {
    var t = Ext2Test{};
    try t.init();
    defer t.done();

    try t.m.assert_directory_has("/", &[_][]const u8{".", "..", "lost+found", "dir", "file1"});
    try t.m.assert_directory_has("/dir", &[_][]const u8{".", "..", "file2"});

    const file1 = try t.m.resolve_file("/file1", .{});
    try test_reading(try file1.get_io_file(),
        \\Hello this is a file
        \\
    );

    const file2 = try t.m.resolve_file("/dir/file2", .{});
    try test_reading(try file2.get_io_file(),
        \\This is another file
        \\
    );

    t.reached_end();
}
