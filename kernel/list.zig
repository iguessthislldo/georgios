const memory = @import("memory.zig");

pub fn List(comptime Type: type) type {
    return struct {
        const Self = @This();

        pub const Element = struct {
            next: ?*Element,
            prev: ?*Element,
            value: Type,
        };

        alloc: *memory.Allocator,
        head: ?*Element = null,
        tail: ?*Element = null,
        len: usize = 0,

        pub fn push_front(self: *Self, value: Type) memory.MemoryError!void {
            const element = try self.alloc.alloc(Element);
            element.value = value;
            element.next = self.head;
            element.prev = null;
            if (self.head) |head| {
                head.prev = element;
            }
            self.head = element;
            if (self.len == 0) {
                self.tail = element;
            }
            self.len += 1;
        }

        pub fn pop_front(self: *Self) memory.MemoryError!?Type {
            if (self.head == null) {
                return null;
            }
            const element = self.head.?;
            if (element.next) |next| {
                next.prev = null;
            }
            self.head = element.next;
            const value = element.value;
            try self.alloc.free(element);
            self.len -= 1;
            if (self.len == 0) {
                self.tail = null;
            }
            return value;
        }

        pub fn push_back(self: *Self, value: Type) memory.MemoryError!void {
            const element = try self.alloc.alloc(Element);
            element.value = value;
            element.next = null;
            element.prev = self.tail;
            if (self.tail) |tail| {
                tail.next = element;
            }
            self.tail = element;
            if (self.len == 0) {
                self.head = element;
            }
            self.len += 1;
        }

        pub fn pop_back(self: *Self) memory.MemoryError!?Type {
            if (self.tail == null) {
                return null;
            }
            const element = self.tail.?;
            if (element.prev) |prev| {
                prev.next = null;
            }
            self.tail = element.prev;
            const value = element.value;
            try self.alloc.free(element);
            self.len -= 1;
            if (self.len == 0) {
                self.head = null;
            }
            return value;
        }
    };
}

test "List" {
    const std = @import("std");
    var alloc = memory.ZigAllocator{};
    alloc.initialize();
    defer alloc.done();
    const UsizeList = List(usize);
    var list = UsizeList{.alloc = &alloc.allocator};
    const nilv: ?usize = null;
    const nile: ?*UsizeList.Element = null;

    // Empty
    std.testing.expectEqual(usize(0), list.len);
    std.testing.expectEqual(nilv, try list.pop_back());
    std.testing.expectEqual(nilv, try list.pop_front());
    std.testing.expectEqual(nile, list.head);
    std.testing.expectEqual(nile, list.tail);

    // Push Some Values
    try list.push_back(1);
    std.testing.expectEqual(usize(1), list.len);
    try list.push_back(2);
    std.testing.expectEqual(usize(2), list.len);
    try list.push_back(3);
    std.testing.expectEqual(usize(3), list.len);

    // pop_back The Values
    std.testing.expectEqual(usize(3), (try list.pop_back()).?);
    std.testing.expectEqual(usize(2), list.len);
    std.testing.expectEqual(usize(2), (try list.pop_back()).?);
    std.testing.expectEqual(usize(1), list.len);
    std.testing.expectEqual(usize(1), (try list.pop_back()).?);

    // It's empty again
    std.testing.expectEqual(usize(0), list.len);
    std.testing.expectEqual(nilv, try list.pop_back());
    std.testing.expectEqual(nilv, try list.pop_front());
    std.testing.expectEqual(nile, list.head);
    std.testing.expectEqual(nile, list.tail);

    // Push Some Values
    try list.push_front(1);
    std.testing.expectEqual(usize(1), list.len);
    try list.push_back(2);
    try list.push_front(3);
    try list.push_front(10);
    std.testing.expectEqual(usize(4), list.len);

    // pop_back The Values
    std.testing.expectEqual(usize(10), (try list.pop_front()).?);
    std.testing.expectEqual(usize(3), (try list.pop_front()).?);
    std.testing.expectEqual(usize(1), (try list.pop_front()).?);
    std.testing.expectEqual(usize(2), (try list.pop_front()).?);

    // It's empty yet again
    std.testing.expectEqual(usize(0), list.len);
    std.testing.expectEqual(nilv, try list.pop_back());
    std.testing.expectEqual(nilv, try list.pop_front());
    std.testing.expectEqual(nile, list.head);
    std.testing.expectEqual(nile, list.tail);
}
