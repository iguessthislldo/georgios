// In memory filesystem.
//
// In addition to using this for a RamDisk, this allows for unit testing the
// virtual filesystem code.

const std = @import("std");
const utils = @import("utils");

const kernel = @import("../kernel.zig");
const List = kernel.List;
const memory = kernel.memory;
const Allocator = memory.Allocator;
const MemoryError = memory.MemoryError;
const io = kernel.io;
const fs = kernel.fs;
const DirIterator = fs.DirIterator;
const Context = fs.Context;
const ResolvePathOpts = fs.ResolvePathOpts;
const Vnode = fs.Vnode;
const Vfilesystem = fs.Vfilesystem;
const Error = fs.Error;
const OpenOpts = fs.OpenOpts;

const RamDisk = @This();

const PageFile = struct {
    const Page = struct {
        buffer: []u8,
        written: usize = 0,
    };

    const PageView = struct {
        page: *Page,
        offset: usize,

        pub fn get_buffer(self: *const PageView, writing: bool) []u8 {
            const end = if (writing) self.page.buffer.len else self.page.written;
            return self.page.buffer[self.offset..end];
        }

        pub fn copy_from(self: *PageView, src: []const u8) usize {
            const copied = utils.memory_copy_truncate(self.get_buffer(true), src);
            self.offset += copied;
            self.page.written = @maximum(self.page.written, self.offset);
            return copied;
        }

        pub fn copy_to(self: *PageView, dest: []u8) usize {
            return utils.memory_copy_truncate(dest, self.get_buffer(false));
        }

        pub fn full(self: *const PageView) bool {
            return self.page.written == self.page.buffer.len;
        }

        pub fn at_end(self: *const PageView) bool {
            return self.offset >= self.page.written;
        }
    };

    const Pages = List(*Page);

    pages: Pages,
    alloc: *Allocator,
    page_alloc: *Allocator,
    page_size: usize,
    total_written: usize = 0,

    pub fn new(alloc: *Allocator, page_alloc: *Allocator, page_size: usize) PageFile {
        return .{
            .pages = .{.alloc = alloc},
            .alloc = alloc,
            .page_alloc = page_alloc,
            .page_size = page_size,
        };
    }

    pub fn done(self: *PageFile) MemoryError!void {
        while (try self.pages.pop_front()) |page| {
            try self.alloc.free_array(page.buffer);
            try self.alloc.free(page);
        }
    }

    fn get_page(self: *PageFile, pos: usize) ?PageView {
        var it = self.pages.iterator();
        var return_page: ?*Page = null;
        var seen: usize = 0;
        var seen_before: usize = 0;
        while (it.next()) |page| {
            seen += page.written;
            if (seen >= pos and pos < (seen_before + self.page_size)) {
                return_page = page;
                break;
            }
            seen_before = seen;
        }
        if (return_page) |p| {
            return PageView{.page = p, .offset = pos - seen_before};
        }
        return null;
    }

    fn append_page(self: *PageFile) MemoryError!PageView {
        const page = try self.alloc.alloc(Page);
        page.* = .{.buffer = try self.page_alloc.alloc_array(u8, self.page_size)};
        try self.pages.push_back(page);
        return PageView{.page = page, .offset = 0};
    }

    fn get_or_create_page(self: *PageFile, pos: usize) MemoryError!PageView {
        // TODO: This doesn't seem like it would handle the case of wanting to
        // write in the middle of a file with multiple full pages. It looks
        // like it would append instead.
        var page = self.get_page(pos);
        if (page == null or page.?.full()) {
            return try self.append_page();
        }
        return page.?;
    }

    fn write_impl(self: *PageFile, pos: *usize, from: []const u8) io.FileError!usize {
        if (from.len == 0) return 0;
        var left: usize = from.len;
        var written: usize = 0;
        while (left > 0) {
            var page = self.get_or_create_page(pos.*) catch return io.FileError.OutOfSpace;
            const prev_page_written = page.page.written;
            const copied = page.copy_from(from[written..]);
            self.total_written = self.total_written - prev_page_written + page.page.written;
            written += copied;
            left -= copied;
            pos.* += copied;
        }
        return written;
    }

    fn read_impl(self: *PageFile, pos: *usize, to: []u8) io.FileError!usize {
        var left: usize = to.len;
        var read: usize = 0;
        while (left > 0) {
            var page = self.get_page(pos.*) orelse break;
            if (page.at_end()) {
                break;
            }
            const copied = page.copy_to(to[read..]);
            read += copied;
            left -= copied;
            pos.* += copied;
        }
        return read;
    }

    fn seek_impl(self: *PageFile, pos: *usize,
            offset: isize, seek_type: io.File.SeekType) io.FileError!usize {
        // TODO: limit is null here, is that right?
        const new_pos = try io.File.generic_seek(
            pos.*, self.total_written, null, offset, seek_type);
        pos.* = new_pos;
        return new_pos;
    }
};

const ContextImpl = struct {
    alloc: *Allocator,
    context: Context,
    page_file: *?PageFile,
    pos: usize,

    io_file: io.File,

    fn new(alloc: *Allocator, node: *Node, opts: OpenOpts) ContextImpl {
        return .{
            .alloc = alloc,
            .context = .{
                .vnode = &node.vnode,
                .open_opts = opts,
                .get_io_file_impl = get_io_file_impl,
                .close_impl = close_impl,
            },
            .page_file = &node.page_file,
            .pos = 0,
            .io_file = .{
                .write_impl = write_impl,
                .read_impl = read_impl,
                .seek_impl = seek_impl,
                .close_impl = io.File.nop.close_impl,
            },
        };
    }

    fn get_io_file_impl(ctx: *Context) Error!*io.File {
        const self = @fieldParentPtr(ContextImpl, "context", ctx);
        if (self.page_file.* != null) {
            return &self.io_file;
        }
        return Error.NotAFile;
    }

    fn write_impl(io_file: *io.File, from: []const u8) io.FileError!usize {
        const self = @fieldParentPtr(ContextImpl, "io_file", io_file);
        return self.page_file.*.?.write_impl(&self.pos, from);
    }

    fn read_impl(io_file: *io.File, to: []u8) io.FileError!usize {
        const self = @fieldParentPtr(ContextImpl, "io_file", io_file);
        return self.page_file.*.?.read_impl(&self.pos, to);
    }

    fn seek_impl(io_file: *io.File,
            offset: isize, seek_type: io.File.SeekType) io.FileError!usize {
        const self = @fieldParentPtr(ContextImpl, "io_file", io_file);
        return self.page_file.*.?.seek_impl(&self.pos, offset, seek_type);
    }

    fn close_impl(ctx: *Context) void {
        const self = @fieldParentPtr(ContextImpl, "context", ctx);
        self.alloc.free(self) catch unreachable;
    }
};

pub const Node = struct {
    const Nodes = std.StringArrayHashMap(*Node);

    const DirIteratorImpl = struct {
        alloc: *Allocator,
        dir_iter: DirIterator,
        returned_self: bool = false,
        returned_parent: bool = false,
        node_iter: Nodes.Iterator,

        fn next_impl(dir_it: *DirIterator) Error!?DirIterator.Result {
            const self = @fieldParentPtr(DirIteratorImpl, "dir_iter", dir_it);
            const node = @fieldParentPtr(Node, "vnode", dir_it.dir);
            if (!self.returned_self) {
                self.returned_self = true;
                return DirIterator.Result{.name = ".", .node = dir_it.dir};
            }
            if (!self.returned_parent) {
                self.returned_parent = true;
                return DirIterator.Result{.name = "..", .node = node.parent};
            }
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
    parent: *Vnode,
    nodes: ?Nodes = null,
    page_file: ?PageFile = null,

    pub fn init(self: *Node, ram_disk: *RamDisk, kind: Vnode.Kind, parent: *Vnode) void {
        self.* = .{
            .ram_disk = ram_disk,
            .vnode = .{
                .fs = &ram_disk.vfs,
                .kind = kind,
                .get_dir_iter_impl = get_dir_iter_impl,
                .create_node_impl = create_node_impl,
                .unlink_impl = unlink_impl,
                .open_new_context_impl = open_new_context_impl,
            },
            .parent = parent,
        };
        if (kind.directory) {
            self.nodes = Nodes.init(ram_disk.alloc.std_allocator());
        }
        if (kind.file) {
            self.page_file = PageFile.new(ram_disk.alloc, ram_disk.page_alloc, ram_disk.page_size);
        }
    }

    fn get_dir_iter_impl(vnode: *Vnode) Error!*DirIterator {
        const self = @fieldParentPtr(Node, "vnode", vnode);
        if (self.nodes) |*nodes| {
            const alloc = self.ram_disk.alloc;
            var impl = try alloc.alloc(DirIteratorImpl);
            impl.* = .{
                .alloc = alloc,
                .dir_iter = .{
                    .dir = vnode,
                    .next_impl = DirIteratorImpl.next_impl,
                    .done_impl = DirIteratorImpl.done_impl,
                },
                .node_iter = nodes.iterator(),
            };
            return &impl.dir_iter;
        }
        return Error.NotADirectory;
    }

    fn create_node_impl(vnode: *Vnode, name: []const u8, kind: Vnode.Kind) Error!*Vnode {
        const self = @fieldParentPtr(Node, "vnode", vnode);
        if (self.nodes) |*nodes| {
            var node = try self.ram_disk.alloc.alloc(Node);
            node.init(self.ram_disk, kind, vnode);
            try nodes.put(name, node);
            return &node.vnode;
        }
        return Error.NotADirectory;
    }

    fn unlink_impl(vnode: *Vnode, name: []const u8) Error!void {
        const self = @fieldParentPtr(Node, "vnode", vnode);
        if (self.nodes) |*nodes| {
            const kv = nodes.fetchOrderedRemove(name).?;
            try kv.value.done();
            try self.ram_disk.alloc.free_array(kv.key);
            try self.ram_disk.alloc.free(kv.value);
        } else {
            return Error.NotADirectory;
        }
    }

    fn open_new_context_impl(vnode: *Vnode, opts: OpenOpts) Error!*Context {
        const self = @fieldParentPtr(Node, "vnode", vnode);
        const alloc = self.ram_disk.alloc;
        var impl = try alloc.alloc(ContextImpl);
        impl.* = ContextImpl.new(alloc, self, opts);
        return &impl.context;
    }

    pub fn done(self: *Node) Error!void {
        if (self.nodes) |*nodes| {
            var it = nodes.iterator();
            while (it.next()) |kv| {
                try kv.value_ptr.*.done();
                try self.ram_disk.alloc.free_array(kv.key_ptr.*);
                try self.ram_disk.alloc.free(kv.value_ptr.*);
            }
            nodes.deinit();
        }
        if (self.page_file) |*page_file| {
            try page_file.done();
        }
    }
};

vfs: Vfilesystem,
alloc: *Allocator,
page_alloc: *Allocator,
page_size: usize,
root_node: Node = undefined,

pub fn init(self: *RamDisk, alloc: *Allocator, page_alloc: *Allocator, page_size: usize) void {
    self.* = .{
        .vfs = .{
            .get_root_vnode_impl = get_root_vnode_impl,
        },
        .alloc = alloc,
        .page_alloc = page_alloc,
        .page_size = page_size,
    };
    self.root_node.init(self, .{.directory = true}, &self.root_node.vnode);
}

fn get_root_vnode_impl(vfs: *Vfilesystem) Error!*Vnode {
    const self = @fieldParentPtr(RamDisk, "vfs", vfs);
    return &self.root_node.vnode;
}

pub fn done(self: *RamDisk) Error!void {
    try self.root_node.done();
}

const RamDiskTest = struct {
    const test_page_size = 4;
    alloc: memory.UnitTestAllocator = .{},
    check_allocs: bool = false,
    rd: RamDisk = undefined,
    rd2: RamDisk = undefined,
    m: fs.Manager = undefined,

    pub fn init(self: *RamDiskTest) void {
        self.alloc.init();
        const galloc = &self.alloc.allocator;
        self.rd.init(galloc, galloc, test_page_size);
        self.rd2.init(galloc, galloc, test_page_size);
        self.m.init(galloc, &self.rd.vfs);
    }

    pub fn reached_end(self: *RamDiskTest) void {
        self.check_allocs = true;
    }

    pub fn done(self: *RamDiskTest) void {
        self.rd.done() catch unreachable;
        self.rd2.done() catch unreachable;
        self.alloc.done_check_if(&self.check_allocs);
    }
};

test "RamDisk: Files and Directories" {
    var t = RamDiskTest{};
    t.init();
    defer t.done();

    // Assert root is empty
    try t.m.assert_directory_has("/", &[_][]const u8{".", ".."});

    // Make a file
    _ = try t.m.create_node("/file1", .{.file = true}, .{});
    // And it should now be available
    try t.m.assert_directory_has("/", &[_][]const u8{".", "..", "file1"});
    // Try to make the same file again
    try std.testing.expectError(Error.AlreadyExists,
        t.m.create_node("/file1", .{.file = true}, .{}));

    // Make a directory
    const dir = try t.m.create_node("/dir", .{.directory = true}, .{});
    // And it should now be available
    try t.m.assert_directory_has("/", &[_][]const u8{".", "..", "file1", "dir"});
    _ = try t.m.resolve_directory("/dir", .{});

    // Make some files in the directory
    _ = try t.m.create_node("/dir/file2", .{.file = true}, .{});
    _ = try t.m.create_node("/dir/file3", .{.file = true}, .{});
    const file_list = [_][]const u8{".", "..", "file2", "file3"};
    // And they should now be there
    try t.m.assert_directory_has("/dir", &file_list);

    // Test directory io read
    {
        const ctx = try dir.open_new_context(.{.ReadOnly = .{.dir = true}});
        defer ctx.close();
        const dir_io = try ctx.get_io_file();
        var buffer: [16]u8 = undefined;
        var count: usize = 0;
        while (true) {
            const read = try dir_io.read(buffer[0..]);
            if (read == 0) break;
            try std.testing.expect(count < file_list.len);
            try std.testing.expectEqualStrings(file_list[count], buffer[0..read]);
            count += 1;
        }
    }

    // Remove file1
    try t.m.unlink("/file1", .{});
    try t.m.assert_directory_has("/", &[_][]const u8{".", "..", "dir"});

    // Try to remove dir
    try std.testing.expectError(Error.DirectoryNotEmpty, t.m.unlink("/dir", .{}));
    // Remove files first
    try t.m.unlink("/dir/file2", .{});
    try t.m.assert_directory_has("/dir", &[_][]const u8{".", "..", "file3"});
    try t.m.unlink("/dir/file3", .{});
    try t.m.assert_directory_has("/dir", &[_][]const u8{".", ".."});
    // Try again
    try t.m.unlink("/dir", .{});

    t.reached_end();
}

test "RamDisk: Write and Read Files" {
    var t = RamDiskTest{};
    t.init();
    defer t.done();

    const a = try t.m.create_node("/a", .{.file = true}, .{});
    const ctx = try a.open_new_context(.{.Write = .{.read = true}});
    defer ctx.close();
    const file = try ctx.get_io_file();

    const str1 = "abc123";
    const len1 = str1.len;
    try std.testing.expectEqual(len1, try file.write(str1));

    var offset: usize = 0;
    var read_buffer: [len1]u8 = undefined;
    while (offset < len1) {
        try std.testing.expectEqual(offset, try file.seek(@intCast(isize, offset), .FromStart));
        try std.testing.expectEqual(len1 - offset, try file.read(read_buffer[offset..]));
        try std.testing.expectEqualStrings(str1[offset..], read_buffer[offset..]);
        offset += 1;
    }
}

test "RamDisk: Mount Another Ram Disk" {
    var t = RamDiskTest{};
    t.init();
    defer t.done();

    // Create some files in root
    _ = try t.m.create_node("/file1", .{.file = true}, .{});
    _ = try t.m.create_node("/file2", .{.file = true}, .{});

    // Mount another ram disk
    _ = try t.m.create_node("/mount", .{.directory = true}, .{});
    try t.m.mount(&t.rd2.vfs, "/mount");

    // Create some files there
    _ = try t.m.create_node("/mount/file3", .{.file = true}, .{});
    _ = try t.m.create_node("/mount/file4", .{.file = true}, .{});

    // Should contain:
    try t.m.assert_directory_has("/", &[_][]const u8{".", "..", "file1", "file2", "mount"});
    try t.m.assert_directory_has("/mount", &[_][]const u8{".", "..", "file3", "file4"});
    // Confirm these are in the seperate filesystems
    try std.testing.expectEqual(@as(usize, 3), t.rd.root_node.nodes.?.count());
    try std.testing.expectEqual(@as(usize, 2), t.rd2.root_node.nodes.?.count());

    // TODO: More tests, like unmount and what happens if we delete a mount point?
}
