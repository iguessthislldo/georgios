// ===========================================================================
// Virtual Filesystem Interface
// ===========================================================================
//
// References:
//   - The main source of inspiration and requirements is
//      "UNIX Internals: The New Frontiers" by Uresh Vahalia
//          Chapter 8 "File System Interface and Framework"

const std = @import("std");

const georgios = @import("georgios");
const utils = @import("utils");
const Guid = utils.Guid;

const ext2 = @import("ext2.zig");
const gpt = @import("gpt.zig");
const io = @import("io.zig");
const memory = @import("memory.zig");
const print = @import("print.zig");
const MappedList = @import("mapped_list.zig").MappedList;
const List = @import("list.zig").List;

pub const Error = georgios.fs.Error;
pub const InitError = ext2.Error || gpt.Error || Guid.Error;
pub const RamDisk = @import("fs/RamDisk.zig");

const FileId = io.File.Id;

fn file_id_eql(a: FileId, b: FileId) bool {
    return a == b;
}

fn file_id_cmp(a: FileId, b: FileId) bool {
    return a > b;
}

/// TODO: Remove
pub const File = ext2.File;

/// TODO: Relocate existing code and remove
pub const Filesystem = struct {
    const OpenFiles = MappedList(FileId, *File, file_id_eql, file_id_cmp);

    impl: ext2.Ext2 = ext2.Ext2{},
    open_files: OpenFiles = undefined,
    next_file_id: FileId = 0,

    pub fn init(self: *Filesystem,
            alloc: *memory.Allocator, block_store: *io.BlockStore) InitError!void {
        var found = false;
        if (gpt.Disk.new(block_store)) |disk| {
            var disk_guid: [Guid.string_size]u8 = undefined;
            try disk.guid.to_string(disk_guid[0..]);
            print.format(
                \\ - Disk GUID is {}
                \\   - Disk partitions entries at LBA {}
                \\   - Disk partitions entries are {}B each
                \\   - Partitions:
                \\
                , .{
                disk_guid,
                disk.partition_entries_lba,
                disk.partition_entry_size,
            });

            var part_it = try disk.partitions();
            defer (part_it.done() catch unreachable);
            while (try part_it.next()) |part| {
                var type_guid: [Guid.string_size]u8 = undefined;
                try part.type_guid.to_string(type_guid[0..]);
                print.format(
                    \\     - Part
                    \\       - {}
                    \\       - {} - {}
                    \\
                    , .{
                    type_guid,
                    part.start,
                    part.end,
                });
                if (part.is_linux()) {
                    // TODO: Acutally see if this the right partition
                    print.string("     - Is Linux!\n");
                    self.impl.offset = part.start * block_store.block_size;
                    found = true;
                }
            }

        } else |e| {
            if (e != gpt.Error.InvalidMbr) {
                return e;
            } else {
                print.string(" - Disk doesn't have a MBR, going to try to use whole " ++
                    "disk as a ext2 filesystem.\n");
                // Else try to use whole disk
                found = true;
            }
        }

        if (found) {
            print.string(" - Filesystem\n");
            try self.impl.init(alloc, block_store);
        } else {
            print.string(" - No Filesystem\n");
        }

        self.open_files = OpenFiles{.alloc = alloc};
    }

    pub fn open(self: *Filesystem, path: []const u8) Error!*File {
        const file = try self.impl.open(path);
        file.io_file.id = self.next_file_id;
        self.next_file_id += 1;
        try self.open_files.push_front(file.io_file.id.?, file);
        return file;
    }

    pub fn file_id_read(self: *Filesystem, id: FileId, to: []u8) io.FileError!usize {
        if (self.open_files.find(id)) |file| {
            return file.io_file.read(to);
        } else {
            return io.FileError.InvalidFileId;
        }
    }

    pub fn file_id_write(self: *Filesystem, id: FileId, from: []const u8) io.FileError!usize {
        _ = from;
        if (self.open_files.find(id)) |file| {
            // TODO
            _ = file;
            @panic("Filesystem.file_id_write called");
        } else {
            return io.FileError.InvalidFileId;
        }
    }

    // TODO: file_id_seek

    pub fn file_id_close(self: *Filesystem, id: FileId) io.FileError!void {
        if (try self.open_files.find_remove(id)) |file| {
            try self.impl.close(file);
        } else {
            return io.FileError.InvalidFileId;
        }
    }

    pub fn resolve_directory_path(self: *Filesystem, path: []const u8) Error![]const u8 {
        return self.impl.resolve_directory_path(path);
    }
};

pub const PathIterator = struct {
    path: []const u8,
    pos: usize = 0,
    absolute: bool,
    trailing_slash: bool,

    pub fn new(path: []const u8) PathIterator {
        var trimmed_path = path;
        var absolute = false;
        var trailing_slash = false;
        if (trimmed_path.len > 0 and trimmed_path[0] == '/') {
            absolute = true;
            trimmed_path = trimmed_path[1..];
        }
        if (trimmed_path.len > 0 and trimmed_path[trimmed_path.len - 1] == '/') {
            trailing_slash = true;
            trimmed_path = trimmed_path[0..trimmed_path.len - 1];
        }
        return PathIterator{
            .path = trimmed_path,
            .absolute = absolute,
            .trailing_slash = trailing_slash,
        };
    }

    fn next_slash(self: *PathIterator) ?usize {
        var i: usize = self.pos;
        while (self.path[i] != '/') {
            i += 1;
            if (i >= self.path.len) return null;
        }
        return i;
    }

    pub fn done(self: *PathIterator) bool {
        return self.pos >= self.path.len;
    }

    pub fn next(self: *PathIterator) ?[]const u8 {
        var component: ?[]const u8 = null;
        while (component == null) {
            if (self.done()) {
                return null;
            }
            if (self.next_slash()) |slash| {
                component = self.path[self.pos..slash];
                self.pos = slash + 1;
            } else {
                component = self.path[self.pos..];
                self.pos = self.path.len;
            }
            if (component.?.len == 0 or utils.memory_compare(component.?, ".")) {
                component = null;
            }
        }
        return component;
    }
};

fn assert_path_iterator(
        path: []const u8,
        expected: []const []const u8,
        absolute: bool,
        trailing_slash: bool) !void {
    var i: usize = 0;
    var it = PathIterator.new(path);
    try std.testing.expectEqual(absolute, it.absolute);
    try std.testing.expectEqual(trailing_slash, it.trailing_slash);
    while (it.next()) |component| {
        try std.testing.expect(i < expected.len);
        try std.testing.expectEqualStrings(expected[i], component);
        i += 1;
    }
    try std.testing.expect(it.done());
    try std.testing.expectEqual(expected.len, i);
}

test "PathIterator" {
    try assert_path_iterator(
        "", &[_][]const u8{}, false, false);

    try assert_path_iterator(
        ".", &[_][]const u8{}, false, false);
    try assert_path_iterator(
        "./", &[_][]const u8{}, false, true);
    try assert_path_iterator(
        ".///////", &[_][]const u8{}, false, true);
    try assert_path_iterator(
        ".//.///.", &[_][]const u8{}, false, false);

    try assert_path_iterator(
        "/", &[_][]const u8{}, true, false);
    try assert_path_iterator(
        "/.", &[_][]const u8{}, true, false);
    try assert_path_iterator(
        "/./", &[_][]const u8{}, true, true);
    try assert_path_iterator(
        "/.///////", &[_][]const u8{}, true, true);
    try assert_path_iterator(
        "/.//.///.", &[_][]const u8{}, true, false);

    try assert_path_iterator(
        "alice", &[_][]const u8{"alice"}, false, false);
    try assert_path_iterator(
        "alice/bob", &[_][]const u8{"alice", "bob"}, false, false);
    try assert_path_iterator(
        "alice/bob/carol", &[_][]const u8{"alice", "bob", "carol"}, false, false);
    try assert_path_iterator(
        "alice/", &[_][]const u8{"alice"}, false, true);
    try assert_path_iterator(
        "alice/bob/", &[_][]const u8{"alice", "bob"}, false, true);
    try assert_path_iterator(
        "alice/bob/carol/", &[_][]const u8{"alice", "bob", "carol"}, false, true);
    try assert_path_iterator(
        "alice/bob/./carol/", &[_][]const u8{"alice", "bob", "carol"}, false, true);
    try assert_path_iterator(
        "alice/bob/../carol/.//./", &[_][]const u8{"alice", "bob", "..", "carol"}, false, true);

    try assert_path_iterator(
        "/alice", &[_][]const u8{"alice"}, true, false);
    try assert_path_iterator(
        "/alice/bob", &[_][]const u8{"alice", "bob"}, true, false);
    try assert_path_iterator(
        "/alice/bob/carol", &[_][]const u8{"alice", "bob", "carol"}, true, false);
    try assert_path_iterator(
        "/alice/", &[_][]const u8{"alice"}, true, true);
    try assert_path_iterator(
        "/alice/bob/", &[_][]const u8{"alice", "bob"}, true, true);
    try assert_path_iterator(
        "/alice/bob/carol/", &[_][]const u8{"alice", "bob", "carol"}, true, true);
    try assert_path_iterator(
        "/alice/bob/./carol/", &[_][]const u8{"alice", "bob", "carol"}, true, true);
    try assert_path_iterator(
        "/alice/bob/../carol/.//./", &[_][]const u8{"alice", "bob", "..", "carol"}, true, true);
}

pub const Path = struct {
    const StrList = List([]const u8);

    alloc: *memory.Allocator,
    absolute: bool = false,
    list: StrList = undefined,

    fn copy_string(self: *const Path, str: []const u8) Error![]u8 {
        const copy = try self.alloc.alloc_array(u8, str.len);
        _ = utils.memory_copy_truncate(copy, str);
        return copy;
    }

    fn push_to_list(self: *Path, list: *StrList, str: []const u8) Error!void {
        try list.push_back(try self.copy_string(str));
    }

    pub fn push_component(self: *Path, str: []const u8) Error!void {
        try self.push_to_list(&self.list, str);
    }

    pub fn pop_component(self: *Path) Error!void {
        if (try self.list.pop_back()) |component| {
            try self.alloc.free_array(component);
        }
    }

    fn path_to_list(self: *Path, list: *StrList, path: []const u8) Error!bool {
        var it = PathIterator.new(path);
        while (it.next()) |component| {
            // Parent of root is root
            if (utils.memory_compare(component, "..") and it.absolute and list.len == 0) {
                continue;
            }
            try self.push_to_list(list, component);
        }
        return it.absolute;
    }

    pub fn set(self: *Path, path: []const u8) Error!void {
        self.absolute = try self.path_to_list(&self.list, path);
    }

    pub fn prepend(self: *Path, path: []const u8) Error!void {
        if (self.absolute) {
            @panic("Can not prepend to an absolute path");
        }

        var new_list = StrList{.alloc = self.alloc};
        self.absolute = try self.path_to_list(&new_list, path);
        new_list.push_back_list(&self.list);
        self.list = new_list;
    }

    pub fn init(self: *Path, path: ?[]const u8) Error!void {
        self.list = .{.alloc = self.alloc};

        if (path) |p| {
            try self.set(p);
        }
    }

    pub fn done(self: *Path) Error!void {
        while (self.list.len > 0) {
            try self.pop_component();
        }
    }

    fn value_if_empty(self: *const Path) []const u8 {
        return if (self.absolute) "/" else ".";
    }

    pub fn get(self: *const Path) Error![]u8 {
        // Calculate size of path string
        var size: usize = 0;
        var iter = self.list.const_iterator();
        while (iter.next()) |component| {
            if (size > 0 or self.absolute) {
                size += 1; // For '/'
            }
            size += component.len;
        }
        if (size == 0) {
            size = 1; // For '.' or '/'
        }

        // Build path string
        iter = self.list.const_iterator();
        var buffer: []u8 = try self.alloc.alloc_array(u8, size);
        var build = utils.ToString{.buffer = buffer};
        while (iter.next()) |component| {
            if (build.got > 0 or self.absolute) {
                try build.string("/");
            }
            try build.string(component);
        }
        if (build.got == 0) {
            try build.string(self.value_if_empty());
        }

        return build.get();
    }

    pub fn filename(self: *const Path) Error![]u8 {
        return try self.copy_string(if (self.list.tail) |tail_node| tail_node.value else self.value_if_empty());
    }
};

fn assert_path(alloc: *memory.Allocator,
        prepend: ?[]const u8, path_str: []const u8, expected: []const u8, expected_filename: []const u8) !void {
    var path = Path{.alloc = alloc};
    try path.init(path_str);
    defer (path.done() catch unreachable);
    if (prepend) |pre| {
        try path.prepend(pre);
    }
    const result_path_str = try path.get();
    try std.testing.expectEqualStrings(expected, result_path_str);
    try alloc.free_array(result_path_str);

    const filename = try path.filename();
    try std.testing.expectEqualStrings(expected_filename, filename);
    try alloc.free_array(filename);
}

test "Path" {
    var alloc = memory.UnitTestAllocator{};
    alloc.init();
    defer alloc.done();
    const galloc = &alloc.allocator;

    try assert_path(galloc, null, "", ".", ".");
    try assert_path(galloc, null, "./", ".", ".");
    try assert_path(galloc, null, "./.", ".", ".");
    try assert_path(galloc, null, "./a/b/c", "a/b/c", "c");
    try assert_path(galloc, null, "./a/b/../c", "a/b/../c", "c");
    try assert_path(galloc, null, "/", "/", "/");
    try assert_path(galloc, null, "/a/b/c", "/a/b/c", "c");
    try assert_path(galloc, null, "/a/b/../c", "/a/b/../c", "c");
    try assert_path(galloc, null, "/a/../a/b/..//c///./.", "/a/../a/b/../c", "c");
    try assert_path(galloc, null, "..", "..", "..");
    try assert_path(galloc, null, "a/../../b", "a/../../b", "b");
    try assert_path(galloc, null, "/..", "/", "/");
    try assert_path(galloc, null, "/../file", "/file", "file");

    try assert_path(galloc, ".", ".", ".", ".");
    try assert_path(galloc, "", "goodbye", "goodbye", "goodbye");
    try assert_path(galloc, "hello", "goodbye", "hello/goodbye", "goodbye");
    try assert_path(galloc, "/", "a", "/a", "a");
}

// Virtual Filesystem
// TODO: mouting filesystems
// TODO: hard and symbolic links
// TODO: different open modes
// TODO: permissions
pub const DirIterator = struct {
    pub const Result = struct {
        name: []const u8,
        node: *Vnode,
    };

    dir: *Vnode,
    current: ?Result = null,
    finished: bool = false,
    next_impl: fn(self: *DirIterator) Error!?Result,
    done_impl: fn(self: *DirIterator) void,

    pub fn next(self: *DirIterator) Error!?Result {
        if (self.finished) {
            return null;
        }
        return self.next_impl(self);
    }

    pub fn done(self: *DirIterator) void {
        return self.done_impl(self);
    }
};

pub const Vnode = struct {
    pub const Kind = struct {
        file: bool = false,
        directory: bool = false,
    };

    fs: *Vfilesystem,
    kind: Kind,
    mounted_here: ?*Vfilesystem = null,

    get_dir_iter_impl: fn(*Vnode) Error!*DirIterator,
    create_node_impl: fn(*Vnode, []const u8, Kind) Error!*Vnode,
    unlink_impl: fn(*Vnode, []const u8) Error!void,
    get_io_file_impl: fn(*Vnode) Error!*io.File,
    close_impl: fn(*Vnode) Error!void,

    pub fn assert_directory(self: *const Vnode) Error!void {
        if (!self.kind.directory) {
            return Error.NotADirectory;
        }
    }

    pub fn assert_file(self: *const Vnode) Error!void {
        if (!self.kind.file) {
            return Error.NotAFile;
        }
    }

    fn node_with_content(self: *Vnode) callconv(.Inline) *Vnode {
        if (self.mounted_here) |other_fs| {
            return other_fs.get_root_vnode();
        }
        return self;
    }

    fn dir_iter_i(self: *Vnode) callconv(.Inline) Error!*DirIterator {
        try self.assert_directory();
        return self.get_dir_iter_impl(self);
    }

    pub fn dir_iter(self: *Vnode) Error!*DirIterator {
        return self.node_with_content().dir_iter_i();
    }

    fn find_in_directory_i(self: *Vnode, name: []const u8) callconv(.Inline) Error!*Vnode {
        var it = try self.dir_iter_i();
        defer it.done();
        while (try it.next()) |result| {
            if (utils.memory_compare(name, result.name)) {
                return result.node;
            }
        }
        return Error.FileNotFound;
    }

    pub fn find_in_directory(self: *Vnode, name: []const u8) Error!*Vnode {
        return self.node_with_content().find_in_directory_i(name);
    }

    fn directory_empty_i(self: *Vnode) callconv(.Inline) Error!bool {
        var it = try self.dir_iter_i();
        defer it.done();
        return (try it.next()) == null;
    }

    pub fn directory_empty(self: *Vnode) Error!bool {
        return self.node_with_content().directory_empty_i();
    }

    fn create_node_i(self: *Vnode, name: []const u8, kind: Kind) callconv(.Inline) Error!*Vnode {
        try self.assert_directory();
        return self.create_node_impl(self, name, kind);
    }

    pub fn create_node(self: *Vnode, name: []const u8, kind: Kind) Error!*Vnode {
        return self.node_with_content().create_node_i(name, kind);
    }

    fn unlink_i(self: *Vnode, name: []const u8) callconv(.Inline) Error!void {
        const vnode_to_unlink = try self.find_in_directory_i(name);
        if (vnode_to_unlink.kind.directory and !try vnode_to_unlink.directory_empty()) {
            return Error.DirectoryNotEmpty;
        }
        try self.unlink_impl(self, name);
    }

    pub fn unlink(self: *Vnode, name: []const u8) Error!void {
        return self.node_with_content().unlink_i(name);
    }

    pub fn get_io_file(self: *Vnode) Error!*io.File {
        return self.get_io_file_impl(self);
    }

    pub fn close(self: *Vnode) Error!void {
        try self.close_impl(self);
    }
};

pub const Vfilesystem = struct {
    get_root_vnode_impl: fn(self: *Vfilesystem) *Vnode,

    pub fn get_root_vnode(self: *Vfilesystem) *Vnode {
        return self.get_root_vnode_impl(self);
    }
};

pub const ResolvePathOpts = struct {
    // Optionally set to get canonical path if set.
    path: ?*[]u8 = null,
    // Optionally set the current working directory.
    cwd: ?[]const u8 = null,
    // Optionally set the starting node for resolution. cwd should be null.
    starting_node: ?*Vnode = null,
    // The resulting node. Will also be the last valid part of the path if there's an error.
    node: ?**Vnode = null,

    pub fn get_cwd(self: *const ResolvePathOpts) []const u8 {
        return self.cwd orelse "/";
    }

    pub fn get_working_copy(self: *const ResolvePathOpts, default_node_ptr_ptr: **Vnode) ResolvePathOpts {
        var ro = self.*;
        if (ro.cwd == null) {
            ro.cwd = "/";
        }
        if (ro.node == null) {
            ro.node = default_node_ptr_ptr;
        }
        return ro;
    }

    pub fn set_node(self: *const ResolvePathOpts, node: *Vnode) void {
        self.node.?.* = node;
    }

    pub fn get_node(self: *const ResolvePathOpts) *Vnode {
        return self.node.?.*;
    }
};

pub const Manager = struct {
    alloc: *memory.Allocator,
    root_fs: *Vfilesystem,

    pub fn init(self: *Manager, alloc: *memory.Allocator, root_fs: *Vfilesystem) void {
        self.* = .{
            .alloc = alloc,
            .root_fs = root_fs,
        };
    }

    pub fn get_root_vnode(self: *Manager) *Vnode {
        return self.root_fs.get_root_vnode();
    }

    fn get_absolute_path(self: *Manager, path_str: []const u8, opts: ResolvePathOpts) Error!Path {
        var path = Path{.alloc = self.alloc};
        try path.init(path_str);
        if (!path.absolute) {
            try path.prepend(opts.get_cwd());
        }
        return path;
    }

    fn resolve_path_i(self: *Manager, raw_path: *Path, opts: ResolvePathOpts) Error!*Vnode {
        var vnode = opts.starting_node orelse self.get_root_vnode();
        var resolved_path = Path{.alloc = self.alloc, .absolute = true};
        try resolved_path.init(null);
        defer (resolved_path.done() catch @panic("resolve_path_i: resolved_path.done()"));
        var it = raw_path.list.const_iterator();
        while (it.next()) |component| {
            vnode = try vnode.find_in_directory(component);
            opts.set_node(vnode);
            if (utils.memory_compare(component, "..")) {
                try resolved_path.pop_component();
            } else {
                try resolved_path.push_component(component);
            }
        }

        if (opts.path) |rp| {
            rp.* = try resolved_path.get();
        }

        opts.set_node(vnode);
        return vnode;
    }

    fn resolve_path(self: *Manager, path_str: []const u8, opts: ResolvePathOpts) Error!*Vnode {
        // See man page path_resolution(7) for reference
        // TODO: Assert path with trailing slash is a directory

        // Get unresolved absolute path
        var path = try self.get_absolute_path(path_str, opts);
        defer (path.done() catch @panic("resolve_path: path.done()"));

        // Find node and build resolved path
        return self.resolve_path_i(&path, opts);
    }

    pub fn resolve_directory(self: *Manager, path_str: []const u8, opts: ResolvePathOpts) Error!*Vnode {
        var dnp: *Vnode = undefined;
        var opts_copy = opts.get_working_copy(&dnp);
        const vnode = try self.resolve_path(path_str, opts_copy);
        try vnode.assert_directory();
        return vnode;
    }

    pub fn resolve_parent_directory(self: *Manager, path_str: []const u8,
            opts: ResolvePathOpts) Error![]const u8 {
        var dnp: *Vnode = undefined;
        var opts_copy = opts.get_working_copy(&dnp);
        var path = try self.get_absolute_path(path_str, opts_copy);
        defer (path.done() catch @panic("create_node: path.done()"));
        const child_name = try path.filename();
        try path.pop_component();
        _ = try self.resolve_path_i(&path, opts_copy);
        return child_name;
    }

    fn resolve_file(self: *Manager, path_str: []const u8, opts: ResolvePathOpts) Error!*Vnode{
        var dnp: *Vnode = undefined;
        var opts_copy = opts.get_working_copy(&dnp);
        const vnode = try self.resolve_path(path_str, opts_copy);
        try vnode.assert_file();
        return vnode;
    }

    pub fn create_node(self: *Manager,
            path_str: []const u8, kind: Vnode.Kind, opts: ResolvePathOpts) Error!*Vnode {
        var dnp: *Vnode = undefined;
        var opts_copy = opts.get_working_copy(&dnp);
        const child_name = try self.resolve_parent_directory(path_str, opts_copy);
        return opts_copy.get_node().create_node(child_name, kind);
    }

    pub fn unlink(self: *Manager, path_str: []const u8, opts: ResolvePathOpts) Error!void {
        var dnp: *Vnode = undefined;
        var opts_copy = opts.get_working_copy(&dnp);
        const child_name = try self.resolve_parent_directory(path_str, opts_copy);
        defer self.alloc.free_array(child_name) catch unreachable;
        try opts_copy.get_node().unlink(child_name);
    }

    pub fn mount(self: *Manager, fs: *Vfilesystem, path: []const u8) Error!void {
        // TODO: Support mounting at any node, for example if the filesystem
        // consists of just a file.
        var opts = ResolvePathOpts{};
        const node = try self.resolve_directory(path, opts);
        if (node.mounted_here != null) {
            return Error.FilesystemAlreadyMountedHere;
        }
        node.mounted_here = fs;
    }
};
