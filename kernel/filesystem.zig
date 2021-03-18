// ===========================================================================
// Virtual Filesystem Interface
// ===========================================================================

// TODO: Support Abstract Filesystem API

const std = @import("std");

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
