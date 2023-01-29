const std = @import("std");
const Allocator = std.mem.Allocator;
pub const Error = Allocator.Error;

const utils = @import("utils.zig");

pub fn List(comptime Type: type) type {
    return struct {
        const Self = @This();

        pub const Node = struct {
            next: ?*Node = null,
            prev: ?*Node = null,
            value: Type,
        };

        alloc: Allocator,
        head: ?*Node = null,
        tail: ?*Node = null,
        len: usize = 0,

        pub fn front(self: *Self) ?Type {
            if (self.head) |node| {
                return node.value;
            }
            return null;
        }

        pub fn back(self: *Self) ?Type {
            if (self.tail) |node| {
                return node.value;
            }
            return null;
        }

        pub fn unlink_node(self: *Self, node_maybe: ?*Node) void {
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

        pub fn destroy_node(self: *Self, node: *Node) void {
            self.alloc.destroy(node);
        }

        pub fn remove_node(self: *Self, node: *Node) void {
            self.unlink_node(node);
            self.destroy_node(node);
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

        pub fn create_node(self: *Self, value: Type) Error!*Node{
            const node = try self.alloc.create(Node);
            node.* = .{.value = value};
            return node;
        }

        pub fn push_front(self: *Self, value: Type) Error!void {
            self.push_front_node(try self.create_node(value));
        }

        pub fn pop_front_node(self: *Self) ?*Node {
            const node = self.head;
            self.unlink_node(node);
            return node;
        }

        pub fn pop_front(self: *Self) ?Type {
            if (self.pop_front_node()) |node| {
                const value = node.value;
                self.destroy_node(node);
                return value;
            }
            return null;
        }

        pub fn bump_node_to_front(self: *Self, node: *Node) void {
            if (self.head == node) {
                return;
            }
            self.unlink_node(node);
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

        pub fn push_back(self: *Self, value: Type) Error!void {
            self.push_back_node(try self.create_node(value));
        }

        pub fn pop_back_node(self: *Self) ?*Node {
            const node = self.tail;
            self.unlink_node(node);
            return node;
        }

        pub fn pop_back(self: *Self) ?Type {
            if (self.pop_back_node()) |node| {
                const value = node.value;
                self.destroy_node(node);
                return value;
            }
            return null;
        }

        pub fn bump_node_to_back(self: *Self, node: *Node) void {
            if (self.tail == node) {
                return;
            }
            self.unlink_node(node);
            self.push_back_node(node);
        }

        pub fn insert_node_before(self: *Self, before_maybe: ?*Node, insert: *Node) void {
            if (before_maybe == null) {
                self.push_back_node(insert);
                return;
            }
            const before = before_maybe.?;
            if (before.prev == insert) {
                return;
            }
            insert.prev = before.prev;
            insert.next = before;
            before.prev = insert;
            if (insert.prev) |after| {
                after.next = insert;
            } else {
                self.head = insert;
            }
            self.len += 1;
        }

        pub fn insert_before(self: *Self, before: ?*Node, value: Type) Error!void {
            self.insert_node_before(before, try self.create_node(value));
        }

        pub fn insert_node_after(self: *Self, after_maybe: ?*Node, insert: *Node) void {
            if (after_maybe == null) {
                self.push_front_node(insert);
                return;
            }
            const after = after_maybe.?;
            if (after.next == insert) {
                return;
            }
            insert.prev = after;
            insert.next = after.next;
            after.next = insert;
            if (insert.next) |before| {
                before.prev = insert;
            } else {
                self.tail = insert;
            }
            self.len += 1;
        }

        pub fn insert_after(self: *Self, after: ?*Node, value: Type) Error!void {
            self.insert_node_after(after, try self.create_node(value));
        }

        pub fn push_back_list(self: *Self, other: *Self) void {
            if (other.head) |other_head| {
                other_head.prev = self.tail;
                if (self.tail) |tail| {
                    tail.next = other_head;
                }
                self.tail = other.tail;
                if (self.len == 0) {
                    self.head = other_head;
                }
                self.len += other.len;
                other.head = null;
                other.tail = null;
                other.len = 0;
            }
        }

        pub fn to_slice(self: *Self) Error![]Type {
            const slice = try self.alloc.alloc(Type, self.len);
            var it = self.iterator();
            var i: usize = 0;
            while (it.next()) |value| {
                slice[i] = value;
                i += 1;
            }
            return slice;
        }

        pub fn clear(self: *Self) void {
            while (self.pop_back_node()) |node| {
                self.destroy_node(node);
            }
        }

        pub const Iterator = struct {
            node: ?*Node,

            pub fn next(self: *Iterator) ?Type {
                if (self.node) |n| {
                    self.node = n.next;
                    return n.value;
                }
                return null;
            }

            pub fn done(self: *const Iterator) bool {
                return self.node == null;
            }
        };

        pub fn iterator(self: *Self) Iterator {
            return Iterator{.node = self.head};
        }

        // TODO: Make generic with Iterator?
        pub const ConstIterator = struct {
            node: ?*const Node,

            pub fn next(self: *ConstIterator) ?Type {
                if (self.node) |n| {
                    self.node = n.next;
                    return n.value;
                }
                return null;
            }

            pub fn done(self: *const ConstIterator) bool {
                return self.node == null;
            }
        };

        pub fn const_iterator(self: *const Self) ConstIterator {
            return ConstIterator{.node = self.head};
        }
    };
}

test "List" {
    const equal = std.testing.expectEqual;

    var ta = utils.TestAlloc{};
    defer ta.deinit(.Panic);
    errdefer ta.deinit(.NoPanic);
    const alloc = ta.alloc();

    const UsizeList = List(usize);
    var list = UsizeList{.alloc = alloc};
    const nilv: ?usize = null;
    const niln: ?*UsizeList.Node = null;

    // Empty
    try equal(@as(usize, 0), list.len);
    try equal(nilv, list.pop_back());
    try equal(nilv, list.pop_front());
    try equal(niln, list.head);
    try equal(niln, list.tail);

    // Push Some Values
    try list.push_back(1);
    try equal(@as(usize, 1), list.len);
    try list.push_back(2);
    try equal(@as(usize, 2), list.len);
    try list.push_back(3);
    try equal(@as(usize, 3), list.len);

    // Test Iterator
    var i: usize = 0;
    const expected = [_]usize{1, 2, 3};
    var it = list.iterator();
    while (it.next()) |actual| {
        try equal(expected[i], actual);
        i += 1;
    }

    // pop_back The Values
    try equal(@as(usize, 3), list.pop_back().?);
    try equal(@as(usize, 2), list.len);
    try equal(@as(usize, 2), list.pop_back().?);
    try equal(@as(usize, 1), list.len);
    try equal(@as(usize, 1), list.pop_back().?);

    // It's empty again
    try equal(@as(usize, 0), list.len);
    try equal(nilv, list.pop_back());
    try equal(nilv, list.pop_front());
    try equal(niln, list.head);
    try equal(niln, list.tail);

    // Push and insert values
    try list.push_front(20);
    // Now: >20<
    const n20 = list.head;
    try equal(@as(usize, 1), list.len);
    try list.push_back(3);
    // Now: 20 >3<
    const n3 = list.tail;
    try list.push_front(10);
    // Now: >10< 20 3
    try list.insert_after(null, 1);
    // Now: >1< 10 20 3
    try list.insert_after(n3, 4);
    // Now: 1 10 20 3 >4<
    try list.insert_before(list.head, 0);
    // Now: >0< 1 10 20 3 4
    try list.insert_after(n3, 30);
    // Now: 0 1 10 20 3 >30< 4
    try list.insert_before(null, 999);
    // Now: 0 1 10 20 3 30 4 >999<
    try list.insert_before(n20, 11);
    // Now: 0 1 10 >11< 20 3 30 4 999
    try list.insert_before(list.tail, 40);
    // Now: 0 1 10 20 3 30 4 >40< 999

    // Test to_slice and using pop_front
    const expected2 = [_]usize{0, 1, 10, 11, 20, 3, 30, 4, 40, 999};
    try equal(@as(usize, expected2.len), list.len);
    const slice = try list.to_slice();
    defer alloc.free(slice);
    for (expected2) |val, n| {
        try equal(expected2[n], val);
        try equal(expected2[n], list.pop_front().?);
    }

    // It's empty yet again
    try equal(@as(usize, 0), list.len);
    try equal(nilv, list.pop_back());
    try equal(nilv, list.pop_front());
    try equal(niln, list.head);
    try equal(niln, list.tail);

    // Clear
    try list.push_back(12);
    try list.push_front(6);
    list.clear();

    // It's empty ... again
    try equal(@as(usize, 0), list.len);
    try equal(nilv, list.pop_back());
    try equal(nilv, list.pop_front());
    try equal(niln, list.head);
    try equal(niln, list.tail);

    // Test push_back_list by adding empty list to empty list
    var other_list = UsizeList{.alloc = alloc};
    list.push_back_list(&other_list);
    try equal(@as(usize, 0), list.len);
    try equal(nilv, list.pop_back());
    try equal(nilv, list.pop_front());
    try equal(niln, list.head);
    try equal(niln, list.tail);

    // Test push_back_list by adding non empty list to empty list
    try other_list.push_back(1);
    try other_list.push_back(3);
    list.push_back_list(&other_list);
    try equal(@as(usize, 0), other_list.len);
    try equal(nilv, other_list.pop_back());
    try equal(nilv, other_list.pop_front());
    try equal(niln, other_list.head);
    try equal(niln, other_list.tail);
    try equal(@as(usize, 2), list.len);

    // Test push_back_list by adding non empty list to non empty list
    try other_list.push_back(5);
    try other_list.push_back(7);
    list.push_back_list(&other_list);
    try equal(@as(usize, 0), other_list.len);
    try equal(nilv, other_list.pop_back());
    try equal(nilv, other_list.pop_front());
    try equal(niln, other_list.head);
    try equal(niln, other_list.tail);
    try equal(@as(usize, 4), list.len);
    try equal(@as(usize, 1), list.pop_front().?);
    try equal(@as(usize, 3), list.pop_front().?);
    try equal(@as(usize, 5), list.pop_front().?);
    try equal(@as(usize, 7), list.pop_front().?);
    try equal(@as(usize, 0), list.len);
    try equal(nilv, list.pop_back());
    try equal(nilv, list.pop_front());
    try equal(niln, list.head);
    try equal(niln, list.tail);
}
