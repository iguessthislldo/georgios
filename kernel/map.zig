const memory = @import("memory.zig");

/// Map implemented using a simple binary tree.
///
/// TODO: Replace with Balancing Tree
///
/// For Reference See:
///     https://en.wikipedia.org/wiki/Binary_search_tree
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

            pub fn replace_child(self: *Node, current_child: *Node, new_child: ?*Node) void {
                if (self.left == current_child) {
                    self.left = new_child;
                } else if (self.right == current_child) {
                    self.right = new_child;
                } else {
                    @panic("Map.replace_child: Not a child of node!");
                }
            }

            pub fn get_child(self: *const Node, right: bool) ?*Node {
                return if (right) self.right else self.left;
            }
        };

        alloc: *memory.Allocator,
        root: ?*Node = null,
        len: usize = 0,

        const FindParentResult = struct {
            parent: *Node,
            leaf: *?*Node,
        };

        fn find_parent(self: *Self, key: KeyType, start_node: *Node) FindParentResult {
            var i = start_node;
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
                const r = self.find_parent(key, self.root.?);
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
            return self.find_parent(key, self.root.?).leaf.*;
        }

        pub fn find(self: *Self, key: KeyType) ?ValueType {
            if (self.find_node(key)) |node| {
                return node.value;
            }
            return null;
        }

        fn replace_node(self: *Self, current: *Node, new: ?*Node) memory.MemoryError!void {
            if (current == self.root) {
                self.root = new;
            } else {
                current.parent.?.replace_child(current, new);
            }
            try self.alloc.free(current);
        }

        pub fn remove_node(self: *Self, node: *Node) memory.MemoryError!void {
            const right_null = node.right == null;
            const left_null = node.left == null;
            if (right_null and left_null) {
                try self.replace_node(node, null);
            } else if (right_null and !left_null) {
                try self.replace_node(node, node.left);
            } else if (!right_null and left_null) {
                try self.replace_node(node, node.right);
            } else {
                const replacement = node.left.?;
                const reattach = node.right.?;
                try self.replace_node(node, replacement);
                const r = self.find_parent(reattach.value, replacement);
                reattach.parent = r.parent;
                r.leaf.* = reattach;
            }
            self.len -= 1;
        }

        pub fn dump_node(self: *Self, node: ?*Node) void {
            if (node == null) {
                @import("std").debug.warn("null");
            } else {
                @import("std").debug.warn("({}: ", node.?.key);
                self.dump_node(node.?.right);
                @import("std").debug.warn(", ");
                self.dump_node(node.?.left);
                @import("std").debug.warn(")");
            }
        }

        pub fn dump(self: *Self) void {
            self.dump_node(self.root);
        }

        pub fn remove(self: *Self, key: KeyType) memory.MemoryError!bool {
            if (self.find_node(key)) |node| {
                try self.remove_node(node);
                return true;
            }
            return false;
        }

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
    _ = try map.insert(10, 12345);
    _ = try map.insert(23, 5678);
    _ = try map.insert(7, 53);
    std.testing.expectEqual(usize(5), map.len);

    // Find Them
    std.testing.expectEqual(usize(12345), map.find(10).?);
    std.testing.expectEqual(usize(44), map.find(1).?);
    std.testing.expectEqual(usize(5678), map.find(23).?);
    std.testing.expectEqual(usize(65), map.find(4).?);
    std.testing.expectEqual(usize(53), map.find(7).?);

    // Try to Find Non-Existent Key
    std.testing.expectEqual(nil, map.find(45));
    std.testing.expectEqual(false, try map.remove(45));

    // Remove Node with Two Children
    std.testing.expectEqual(true, try map.remove(10));
    std.testing.expectEqual(usize(4), map.len);

    // Remove the Rest
    std.testing.expectEqual(true, try map.remove(1));
    std.testing.expectEqual(true, try map.remove(23));
    std.testing.expectEqual(true, try map.remove(4));
    std.testing.expectEqual(true, try map.remove(7));
    std.testing.expectEqual(usize(0), map.len);

    // Try to Find Keys That Once Existed
    std.testing.expectEqual(nil, map.find(1));
    std.testing.expectEqual(nil, map.find(4));
}
