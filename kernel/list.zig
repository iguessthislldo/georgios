const memory = @import("memory.zig");

pub fn List(comptime Type: type) type {
    return struct {
        const Self = @This();

        pub const Node = struct {
            next: ?*Node,
            prev: ?*Node,
            value: Type,
        };

        alloc: *memory.Allocator,
        head: ?*Node = null,
        tail: ?*Node = null,
        len: usize = 0,

        pub fn remove_node(self: *Self, node_maybe: ?*Node) void {
            if (node_maybe) |node| {
                if (node.next) |next| {
                    next.prev = node.prev;
                }
                if (node.prev) |prev| {
                    prev.next = node.next;
                }
                if (node == self.head) {
                    self.head = node.next;
                }
                if (node == self.tail) {
                    self.tail = node.prev;
                }
                self.len -= 1;
            }
        }

        pub fn push_front_node(self: *Self, node: *Node) void {
            node.next = self.head;
            node.prev = null;
            if (self.head) |head| {
                head.prev = node;
            }
            self.head = node;
            if (self.len == 0) {
                self.tail = node;
            }
            self.len += 1;
        }

        pub fn push_front(self: *Self, value: Type) memory.MemoryError!void {
            const node = try self.alloc.alloc(Node);
            node.value = value;
            self.push_front_node(node);
        }

        pub fn pop_front_node(self: *Self) ?*Node {
            const node = self.head;
            self.remove_node(node);
            return node;
        }

        pub fn pop_front(self: *Self) memory.MemoryError!?Type {
            if (self.pop_front_node()) |node| {
                const value = node.value;
                try self.alloc.free(node);
                return value;
            }
            return null;
        }

        pub fn bump_node_to_front(self: *Self, node: *Node) void {
            if (self.head == node) {
                return;
            }
            self.remove_node(node);
            self.push_front_node(node);
        }

        pub fn push_back_node(self: *Self, node: *Node) void {
            node.next = null;
            node.prev = self.tail;
            if (self.tail) |tail| {
                tail.next = node;
            }
            self.tail = node;
            if (self.len == 0) {
                self.head = node;
            }
            self.len += 1;
        }

        pub fn push_back(self: *Self, value: Type) memory.MemoryError!void {
            const node = try self.alloc.alloc(Node);
            node.value = value;
            self.push_back_node(node);
        }

        pub fn pop_back_node(self: *Self) ?*Node {
            const node = self.tail;
            self.remove_node(node);
            return node;
        }

        pub fn pop_back(self: *Self) memory.MemoryError!?Type {
            if (self.pop_back_node()) |node| {
                const value = node.value;
                try self.alloc.free(node);
                return value;
            }
            return null;
        }

        pub fn bump_node_to_back(self: *Self, node: *Node) void {
            if (self.tail == node) {
                return;
            }
            self.remove_node(node);
            self.push_back_node(node);
        }
    };
}

test "List" {
    const std = @import("std");
    const equal = std.testing.expectEqual;

    var alloc = memory.UnitTestAllocator{};
    alloc.initialize();
    defer alloc.done();

    const UsizeList = List(usize);
    var list = UsizeList{.alloc = &alloc.allocator};
    const nilv: ?usize = null;
    const niln: ?*UsizeList.Node = null;

    // Empty
    equal(@as(usize, 0), list.len);
    equal(nilv, try list.pop_back());
    equal(nilv, try list.pop_front());
    equal(niln, list.head);
    equal(niln, list.tail);

    // Push Some Values
    try list.push_back(1);
    equal(@as(usize, 1), list.len);
    try list.push_back(2);
    equal(@as(usize, 2), list.len);
    try list.push_back(3);
    equal(@as(usize, 3), list.len);

    // pop_back The Values
    equal(@as(usize, 3), (try list.pop_back()).?);
    equal(@as(usize, 2), list.len);
    equal(@as(usize, 2), (try list.pop_back()).?);
    equal(@as(usize, 1), list.len);
    equal(@as(usize, 1), (try list.pop_back()).?);

    // It's empty again
    equal(@as(usize, 0), list.len);
    equal(nilv, try list.pop_back());
    equal(nilv, try list.pop_front());
    equal(niln, list.head);
    equal(niln, list.tail);

    // Push Some Values
    try list.push_front(1);
    equal(@as(usize, 1), list.len);
    try list.push_back(2);
    try list.push_front(3);
    try list.push_front(10);
    equal(@as(usize, 4), list.len);

    // pop_back The Values
    equal(@as(usize, 10), (try list.pop_front()).?);
    equal(@as(usize, 3), (try list.pop_front()).?);
    equal(@as(usize, 1), (try list.pop_front()).?);
    equal(@as(usize, 2), (try list.pop_front()).?);

    // It's empty yet again
    equal(@as(usize, 0), list.len);
    equal(nilv, try list.pop_back());
    equal(nilv, try list.pop_front());
    equal(niln, list.head);
    equal(niln, list.tail);
}
