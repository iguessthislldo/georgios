// In memory filesystem
// TODO: Reading and Wrting

const std = @import("std");
const utils = @import("utils");

const kernel = @import("../kernel.zig");
const List = kernel.List;
const memory = kernel.memory;
const io = kernel.io;
const fs = kernel.fs;
const DirIterator = fs.DirIterator;
const ResolvedVnode = fs.ResolvedVnode;
const Vnode = fs.Vnode;
const Vfilesystem = fs.Vfilesystem;
const Error = fs.Error;

const RamDisk = @This();

pub const Node = struct {
    const Nodes = std.StringArrayHashMap(*Node);

    const DirIteratorImpl = struct {
        alloc: *memory.Allocator,
        dir_iter: DirIterator,
        node_iter: Nodes.Iterator,

        fn next_impl(dir_it: *DirIterator) Error!?DirIterator.Result {
            const self = @fieldParentPtr(DirIteratorImpl, "dir_iter", dir_it);
            if (self.node_iter.next()) |kv| {
                return DirIterator.Result{.name = kv.key_ptr.*, .node = &kv.value_ptr.*.vnode};
            }
            return null;
        }

        fn done_impl(dir_it: *DirIterator) void {
            const self = @fieldParentPtr(DirIteratorImpl, "dir_iter", dir_it);
            self.alloc.free(self) catch @panic("RamDisk DirIterator done");
        }
    };

    ram_disk: *RamDisk,
    vnode: Vnode,
    nodes: Nodes,

    pub fn init(self: *Node, ram_disk: *RamDisk, kind: Vnode.Kind) void {
        self.* = .{
            .ram_disk = ram_disk,
            .vnode = .{
                .fs = &ram_disk.vfs,
                .kind = kind,
                .get_dir_iter_impl = get_dir_iter_impl,
                .create_node_impl = create_node_impl,
                .unlink_impl = unlink_impl,
                .get_io_file_impl = get_io_file_impl,
                .close_impl = close_impl,
            },
            .nodes = Nodes.init(ram_disk.alloc.std_allocator()),
        };
    }

    fn get_dir_iter_impl(vnode: *Vnode) Error!*DirIterator {
        const dir_node = @fieldParentPtr(Node, "vnode", vnode);
        const alloc = dir_node.ram_disk.alloc;
        var impl = try alloc.alloc(DirIteratorImpl);
        impl.* = .{
            .alloc = alloc,
            .dir_iter = .{
                .dir = vnode,
                .next_impl = DirIteratorImpl.next_impl,
                .done_impl = DirIteratorImpl.done_impl,
            },
            .node_iter = dir_node.nodes.iterator(),
        };
        return &impl.dir_iter;
    }

    fn create_node_impl(vnode: *Vnode, name: []const u8, kind: Vnode.Kind) Error!*Vnode {
        const self = @fieldParentPtr(Node, "vnode", vnode);
        var node = try self.ram_disk.alloc.alloc(Node);
        node.init(self.ram_disk, kind);
        try self.nodes.put(name, node);
        return &node.vnode;
    }

    fn unlink_impl(vnode: *Vnode, name: []const u8) Error!void {
        const self = @fieldParentPtr(Node, "vnode", vnode);
        const kv = self.nodes.fetchOrderedRemove(name).?;
        try kv.value.done();
        try self.ram_disk.alloc.free_array(kv.key);
        try self.ram_disk.alloc.free(kv.value);
    }

    fn get_io_file_impl(vnode: *Vnode) ?*io.File {
        const self = @fieldParentPtr(Node, "vnode", vnode);
        _ = self;
        return null;
    }

    fn close_impl(vnode: *Vnode) Error!void {
        _ = vnode;
    }

    pub fn done(self: *Node) Error!void {
        var it = self.nodes.iterator();
        while (it.next()) |kv| {
            try kv.value_ptr.*.done();
            try self.ram_disk.alloc.free_array(kv.key_ptr.*);
            try self.ram_disk.alloc.free(kv.value_ptr.*);
        }
        self.nodes.deinit();
    }
};

vfs: Vfilesystem,
alloc: *memory.Allocator,
big_alloc: *memory.Allocator,
root_node: Node = undefined,

pub fn init(self: *RamDisk, alloc: *memory.Allocator, big_alloc: *memory.Allocator) void {
    self.* = .{
        .vfs = .{
            .get_root_vnode_impl = get_root_vnode_impl,
        },
        .alloc = alloc,
        .big_alloc = big_alloc,
    };
    self.root_node.init(self, .{.directory = true});
}

fn get_root_vnode_impl(vfs: *Vfilesystem) *Vnode {
    const self = @fieldParentPtr(RamDisk, "vfs", vfs);
    return &self.root_node.vnode;
}

pub fn done(self: *RamDisk) Error!void {
    try self.root_node.done();
}

const RamDiskTest = struct {
    pub fn get_cwd() ?[]const u8 {
        return "/";
    }

    alloc: memory.UnitTestAllocator = .{},
    check_allocs: bool = false,
    rd: RamDisk = undefined,
    m: fs.Manager = undefined,

    pub fn init(self: *RamDiskTest) void {
        self.alloc.init();
        const galloc = &self.alloc.allocator;
        self.rd.init(galloc, galloc);
        self.m.init(galloc, &self.rd.vfs, get_cwd);
    }

    pub fn reached_end(self: *RamDiskTest) void {
        self.check_allocs = true;
    }

    pub fn done(self: *RamDiskTest) void {
        self.rd.done() catch unreachable;
        self.alloc.done_check_if(&self.check_allocs);
    }

    fn assert_directory_has(self: *RamDiskTest, path: []const u8, expected: []const []const u8) !void {
        var count: usize = 0;
        var r = ResolvedVnode{};
        try self.m.resolve_directory(path, &r);
        var it = try r.node.?.dir_iter();
        defer it.done();
        while (try it.next()) |item| {
            try std.testing.expect(count < expected.len);
            try std.testing.expectEqualStrings(expected[count], item.name);
            count += 1;
        }
        try std.testing.expectEqual(expected.len, count);
    }
};

test "RamDisk: Files and Directories" {
    var t = RamDiskTest{};
    t.init();
    defer t.done();

    // Assert root is empty
    try t.assert_directory_has("/", &[_][]const u8{});

    // Make a file
    _ = try t.m.create_node("/file1", .{.file = true});
    // And it should now be available
    try t.assert_directory_has("/", &[_][]const u8{"file1"});

    // Make a directory
    _ = try t.m.create_node("/dir", .{.directory = true});
    // And it should now be available
    try t.assert_directory_has("/", &[_][]const u8{"file1", "dir"});
    var dir_resolved = ResolvedVnode{};
    try t.m.resolve_directory("/dir", &dir_resolved);

    // Make some files in the directory
    _ = try t.m.create_node("/dir/file2", .{.file = true});
    _ = try t.m.create_node("/dir/file3", .{.file = true});
    // And they should now be there
    try t.assert_directory_has("/dir", &[_][]const u8{"file2", "file3"});

    // Remove file1
    try t.m.unlink("/file1");
    try t.assert_directory_has("/", &[_][]const u8{"dir"});

    // Try to remove dir
    try std.testing.expectError(Error.DirectoryNotEmpty, t.m.unlink("/dir"));
    // Remove files first
    try t.m.unlink("/dir/file2");
    try t.assert_directory_has("/dir", &[_][]const u8{"file3"});
    try t.m.unlink("/dir/file3");
    try t.assert_directory_has("/dir", &[_][]const u8{});
    // Try again
    try t.m.unlink("/dir");

    t.reached_end();
}
