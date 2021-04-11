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

const utils = @import("utils");
const Guid = utils.Guid;

const ext2 = @import("ext2.zig");
const gpt = @import("gpt.zig");
const io = @import("io.zig");
const memory = @import("memory.zig");
const print = @import("print.zig");

pub const Error = ext2.Error || gpt.Error || Guid.Error;

/// TODO: Make Abstract
pub const File = ext2.File;

/// TODO: Make Abstract
pub const Filesystem = struct {
    impl: ext2.Ext2 = ext2.Ext2{},

    pub fn init(self: *Filesystem,
            alloc: *memory.Allocator, block_store: *io.BlockStore) Error!void {
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
                }
            }

            // TODO: If partition isn't found?

        } else |e| {
            if (e != gpt.Error.InvalidMbr) {
                return e;
            } else {
                print.string(" - Disk doesn't have a MBR, going to try to use whole " ++
                    "disk as a ext2 filesystem.\n");
                // Else try to use whole disk
            }
        }

        try self.impl.init(alloc, block_store);
    }

    pub fn open(self: *Filesystem, path: []const u8) Error!*File {
        return self.impl.open(path);
    }
};

/// TODO
pub const Filesystems = struct {
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
        var clean_path = path;
        var absolute = false;
        var trailing_slash = false;
        if (clean_path.len > 0 and clean_path[0] == '/') {
            absolute = true;
            clean_path = clean_path[1..];
        }
        if (clean_path.len > 0 and clean_path[clean_path.len - 1] == '/') {
            trailing_slash = true;
            clean_path = clean_path[0..clean_path.len - 1];
        }
        return PathIterator{
            .path = clean_path,
            .absolute = absolute,
            .trailing_slash = trailing_slash
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
        if (self.done()) return null;
        var component: []const u8 = undefined;
        if (self.next_slash()) |slash| {
            component = self.path[self.pos..slash];
            self.pos = slash + 1;
        } else {
            component = self.path[self.pos..];
            self.pos = self.path.len;
        }
        return component;
    }
};

fn assert_path_iterator(
        path: []const u8,
        expected: []const []const u8,
        absolute: bool, trailing_slash: bool) void {
    var i: usize = 0;
    var it = PathIterator.new(path);
    std.testing.expectEqual(absolute, it.absolute);
    std.testing.expectEqual(trailing_slash, it.trailing_slash);
    while (it.next()) |component| {
        std.testing.expectEqualStrings(expected[i], component);
        i += 1;
    }
    std.testing.expect(it.done());
    std.testing.expectEqual(i, expected.len);
}

test "PathIterator" {
    assert_path_iterator(
        "", &[_][]const u8{}, false, false);
    assert_path_iterator(
        "alice", &[_][]const u8{"alice"}, false, false);
    assert_path_iterator(
        "alice/bob", &[_][]const u8{"alice", "bob"}, false, false);
    assert_path_iterator(
        "alice/bob/carol", &[_][]const u8{"alice", "bob", "carol"}, false, false);
    assert_path_iterator(
        "alice/", &[_][]const u8{"alice"}, false, true);
    assert_path_iterator(
        "alice/bob/", &[_][]const u8{"alice", "bob"}, false, true);
    assert_path_iterator(
        "alice/bob/carol/", &[_][]const u8{"alice", "bob", "carol"}, false, true);
    assert_path_iterator(
        "/", &[_][]const u8{}, true, false);
    assert_path_iterator(
        "/alice", &[_][]const u8{"alice"}, true, false);
    assert_path_iterator(
        "/alice/bob", &[_][]const u8{"alice", "bob"}, true, false);
    assert_path_iterator(
        "/alice/bob/carol", &[_][]const u8{"alice", "bob", "carol"}, true, false);
    assert_path_iterator(
        "/alice/", &[_][]const u8{"alice"}, true, true);
    assert_path_iterator(
        "/alice/bob/", &[_][]const u8{"alice", "bob"}, true, true);
    assert_path_iterator(
        "/alice/bob/carol/", &[_][]const u8{"alice", "bob", "carol"}, true, true);
}
