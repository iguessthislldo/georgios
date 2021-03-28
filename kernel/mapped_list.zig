const memory = @import("memory.zig");
const Map = @import("map.zig").Map;
const List = @import("list.zig").List;

pub fn MappedList(comptime KeyType: type, comptime ValueType: type,
        comptime eql: fn(a: KeyType, b: KeyType) bool,
        comptime cmp: fn(a: KeyType, b: KeyType) bool) type {
    return struct {
        const Self = @This();

        const MapType = Map(KeyType, *Node, eql, cmp);
        const ListType = List(*Node);
        const Node = struct {
            map: MapType.Node,
            list: ListType.Node,
            value: ValueType,
        };

        alloc: *memory.Allocator,
        map: MapType = MapType{.alloc = undefined},
        list: ListType = ListType{.alloc = undefined},

        pub fn len(self: *Self) usize {
            if (self.map.len != self.list.len) {
                @panic("MappedList len out of sync!");
            }
            return self.map.len;
        }

        pub fn find(self: *Self, key: KeyType) ?ValueType {
            const node_maybe = self.map.find_node(key);
            if (node_maybe == null) {
                return null;
            }
            return node_maybe.?.value.value;
        }

        pub fn push_front(self: *Self, key: KeyType, value: ValueType) memory.MemoryError!void {
            const node = try self.alloc.alloc(Node);
            node.map.right = null;
            node.map.left = null;
            node.map.key = key;
            node.map.value = node;
            node.list.value = node;
            node.value = value;
            self.map.insert_node(&node.map);
            self.list.push_front_node(&node.list);
        }

        pub fn pop_front(self: *Self) memory.MemoryError!?ValueType {
            const node_maybe = self.list.pop_front_node();
            if (node_maybe == null) {
                return null;
            }
            const node = node_maybe.?.value;
            self.map.remove_node(&node.map);
            const value = node.value;
            try self.alloc.free(node);
            return value;
        }

        pub fn find_bump_to_front(self: *Self, key: KeyType) ?ValueType {
            const node_maybe = self.map.find_node(key);
            if (node_maybe == null) {
                return null;
            }
            const node = node_maybe.?.value;
            self.list.bump_node_to_front(&node.list);
            return node.value;
        }

        pub fn push_back(self: *Self, key: KeyType, value: ValueType) memory.MemoryError!void {
            const node = try self.alloc.alloc(Node);
            node.map.right = null;
            node.map.left = null;
            node.map.key = key;
            node.map.value = node;
            node.list.value = node;
            node.value = value;
            self.map.insert_node(&node.map);
            self.list.push_back_node(&node.list);
        }

        pub fn pop_back(self: *Self) memory.MemoryError!?ValueType {
            const node_maybe = self.list.pop_back_node();
            if (node_maybe == null) {
                return null;
            }
            const node = node_maybe.?.value;
            self.map.remove_node(&node.map);
            const value = node.value;
            try self.alloc.free(node);
            return value;
        }

        pub fn find_bump_to_back(self: *Self, key: KeyType) ?ValueType {
            const node_maybe = self.map.find_node(key);
            if (node_maybe == null) {
                return null;
            }
            const node = node_maybe.?.value;
            self.list.bump_node_to_back(&node.list);
            return node.value;
        }

        pub fn find_remove(self: *Self, key: KeyType) memory.MemoryError!?ValueType {
            const node_maybe = self.map.find_node(key);
            if (node_maybe == null) {
                return null;
            }
            const node = node_maybe.?.value;
            self.list.remove_node(&node.list);
            self.map.remove_node(&node.map);
            const value = node.value;
            try self.alloc.free(node);
            return value;
        }
    };
}

fn usize_eql(a: usize, b: usize) bool {
    return a == b;
}

fn usize_cmp(a: usize, b: usize) bool {
    return a > b;
}

test "MappedList" {
    const std = @import("std");
    const equal = std.testing.expectEqual;

    var alloc = memory.UnitTestAllocator{};
    alloc.init();
    defer alloc.done();

    const UsizeUsizeMappedList = MappedList(usize, usize, usize_eql, usize_cmp);
    var ml = UsizeUsizeMappedList{.alloc = &alloc.allocator};
    const nil: ?usize = null;

    // Empty
    equal(@as(usize, 0), ml.len());
    equal(nil, ml.find(100));

    // Push and Pop from Front
    try ml.push_front(1, 2);
    equal(@as(usize, 1), ml.len());
    equal(@as(usize, 2), ml.find(1).?);
    equal(@as(usize, 2), (try ml.pop_front()).?);
    equal(@as(usize, 0), ml.len());

    // Empty
    equal(@as(usize, 0), ml.len());
    equal(nil, ml.find(1));

    // Push and Pop from Back
    try ml.push_back(5, 7);
    equal(@as(usize, 1), ml.len());
    equal(@as(usize, 7), ml.find(5).?);
    equal(@as(usize, 7), (try ml.pop_back()).?);
    equal(@as(usize, 0), ml.len());

    // Empty
    equal(@as(usize, 0), ml.len());
    equal(nil, ml.find(5));

    // Push and Pop Several Times From Both Directions
    try ml.push_front(11, 1);
    try ml.push_front(22, 2);
    try ml.push_back(123, 456);
    try ml.push_back(33, 3);
    try ml.push_front(44, 4);
    try ml.push_back(55, 5);

    // 44: 4, 22: 2, 11: 1, 123: 456, 33: 3, 55: 5
    equal(@as(usize, 456), (try ml.find_remove(123)).?);

    // 44: 4, 22: 2, 11: 1, 33: 3, 55: 5
    equal(@as(usize, 5), ml.len());
    equal(@as(usize, 1), ml.find(11).?);
    equal(@as(usize, 2), ml.find(22).?);
    equal(@as(usize, 3), ml.find(33).?);
    equal(@as(usize, 4), ml.find(44).?);
    equal(@as(usize, 5), ml.find(55).?);
    equal(nil, ml.find(5));
    equal(@as(usize, 4), ml.find_bump_to_front(44).?);
    equal(@as(usize, 5), ml.find_bump_to_back(55).?);
    equal(@as(usize, 4), (try ml.pop_front()).?);
    // 22: 2, 11: 1, 33: 3, 55: 5
    equal(@as(usize, 5), (try ml.pop_back()).?);
    // 22: 2, 11: 1, 33: 3
    equal(@as(usize, 2), ml.find_bump_to_back(22).?);
    // 11: 1, 33: 3, 22: 2
    try ml.push_back(66, 6);
    // 11: 1, 33: 3, 22: 2, 66: 6
    equal(@as(usize, 3), ml.find_bump_to_front(33).?);
    // 33: 3, 11: 1, 22: 2, 66: 6
    equal(@as(usize, 3), ml.find(33).?);
    equal(@as(usize, 4), ml.len());
    equal(@as(usize, 6), (try ml.pop_back()).?);
    // 33: 3, 11: 1, 22: 2
    equal(@as(usize, 2), (try ml.pop_back()).?);
    // 33: 3, 11: 1
    equal(@as(usize, 1), (try ml.pop_back()).?);
    // 33: 3
    equal(@as(usize, 3), (try ml.pop_back()).?);

    // Empty
    equal(@as(usize, 0), ml.len());
    equal(nil, ml.find(5));
    equal(nil, ml.find(55));
    equal(nil, try ml.pop_back());
    equal(nil, try ml.pop_front());
}
