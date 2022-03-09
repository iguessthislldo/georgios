// ===========================================================================
// Virtual Filesystem Interface
// ===========================================================================
// TODO: Acutally Make It Virtual
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

const FileId = io.File.Id;

fn file_id_eql(a: FileId, b: FileId) bool {
    return a == b;
}

fn file_id_cmp(a: FileId, b: FileId) bool {
    return a > b;
}

/// TODO: Make Abstract
pub const File = ext2.File;

/// TODO: Make Abstract
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
        if (self.open_files.find(id)) |file| {
            // TODO
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

pub const Manager = struct {
    root: *Filesystem,
};

/// TODO
pub const Directory = struct {
    mount: ?*Filesystem = null,
};

// File System Implementation Management / Mounting
// Root of File System
// On Disk File Structure?
// Directory Structure
// Directory Contents Iterator

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
