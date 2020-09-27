const memory = @import("memory.zig");

pub fn Map(comptime KeyType: type, comptime ValueType: type,
        comptime eql: fn(a: KeyType, b: KeyType) bool,
        comptime cmp: fn(a: KeyType, b: KeyType) bool) type {
    return struct {
        const Self = @This();

        pub const Node = struct {
            left: ?*Node,
            right: ?*Node,
            parent: ?*Node,
            key: KeyType,
            value: ValueType,
        };

        alloc: *memory.Allocator,
        root: ?*Node = null,
        len: usize = 0,

        const FindParentResult = struct {
            parent: *Node,
            leaf: *?*Node,
        };

        fn find_parent(self: *Self, key: KeyType) FindParentResult {
            var i = self.root.?;
            while (true) {
                if (cmp(key, i.key)) {
                    if (i.right == null or eql(key, i.right.?.key)) {
                        return FindParentResult{.parent = i, .leaf = &i.right};
                    } else {
                        i = i.right.?;
                    }
                } else {
                    if (i.left == null or eql(key, i.left.?.key)) {
                        return FindParentResult{.parent = i, .leaf = &i.left};
                    } else {
                        i = i.left.?;
                    }
                }
            }
        }

        pub fn insert(self: *Self, key: KeyType, value: ValueType) memory.MemoryError!*Node {
            const node = try self.alloc.alloc(Node);
            node.left = null;
            node.right = null;
            node.key = key;
            node.value = value;

            if (self.root == null) {
                node.parent = null;
                self.root = node;
            } else {
                const r = self.find_parent(key);
                node.parent = r.parent;
                r.leaf.* = node;
            }
            self.len += 1;

            return node;
        }

        pub fn find_node(self: *Self, key: KeyType) ?*Node {
            if (self.root == null) {
                return null;
            }
            if (eql(key, self.root.?.key)) {
                return self.root;
            }
            return self.find_parent(key).leaf.*;
        }

        pub fn find(self: *Self, key: KeyType) ?ValueType {
            if (self.find_node(key)) |node| {
                return node.value;
            }
            return null;
        }

        // TODO: Remove
        // TODO: Iterate
    };
}

fn usize_eql(a: usize, b: usize) bool {
    return a == b;
}

fn usize_cmp(a: usize, b: usize) bool {
    return a > b;
}

test "Map" {
    const std = @import("std");
    var alloc = memory.ZigAllocator{};
    alloc.initialize();
    defer alloc.done();

    const UsizeUsizeMap = Map(usize, usize, usize_eql, usize_cmp);
    var map = UsizeUsizeMap{.alloc = &alloc.allocator};
    const nil: ?usize = null;

    // Empty
    std.testing.expectEqual(usize(0), map.len);
    std.testing.expectEqual(nil, map.find(45));

    // Insert Some Values
    _ = try map.insert(4, 65);
    std.testing.expectEqual(usize(1), map.len);
    _ = try map.insert(1, 44);
    std.testing.expectEqual(usize(2), map.len);
    _ = try map.insert(10, 12345);
    std.testing.expectEqual(usize(3), map.len);
    _ = try map.insert(23, 5678);
    std.testing.expectEqual(usize(4), map.len);

    // Find Them
    std.testing.expectEqual(usize(12345), map.find(10).?);
    std.testing.expectEqual(usize(44), map.find(1).?);
    std.testing.expectEqual(usize(5678), map.find(23).?);
    std.testing.expectEqual(usize(65), map.find(4).?);

    // Try to Find Non-Existent Key Again
    std.testing.expectEqual(nil, map.find(45));
}
