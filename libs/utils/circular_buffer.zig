const std = @import("std");

/// What to discard if there is no more room.
const CircularBufferDiscard = enum {
    DiscardNewest,
    DiscardOldest,
};

pub fn CircularBuffer(
        comptime Type: type, len_arg: usize, discard: CircularBufferDiscard) type {
    return struct {
        const Self = @This();
        const max_len = len_arg;

        contents: [max_len]Type = undefined,
        start: usize = 0,
        len: usize = 0,

        pub fn reset(self: *Self) void {
            self.start = 0;
            self.len = 0;
        }

        fn wrapped_offset(pos: usize, offset: usize) callconv(.Inline) usize {
            return (pos + offset) % max_len;
        }

        fn increment(pos: *usize) callconv(.Inline) void {
            pos.* = wrapped_offset(pos.*, 1);
        }

        pub fn push(self: *Self, value: Type) void {
            if (self.len == max_len) {
                if (discard == .DiscardNewest) {
                    return;
                } else { // DiscardOldest
                    increment(&self.start);
                }
            } else {
                self.len += 1;
            }
            self.contents[wrapped_offset(self.start, self.len - 1)] = value;
        }

        pub fn pop(self: *Self) ?Type {
            if (self.len == 0) return null;
            self.len -= 1;
            defer increment(&self.start);
            return self.contents[self.start];
        }

        pub fn get(self: *const Self, offset: usize) ?Type {
            if (offset >= self.len) return null;
            return self.contents[wrapped_offset(self.start, offset)];
        }

        pub fn peek_start(self: *const Self) ?Type {
            return self.get(0);
        }

        pub fn peek_end(self: *const Self) ?Type {
            if (self.len == 0) return null;
            return self.get(self.len - 1);
        }
    };
}

fn test_circular_buffer(comptime discard: CircularBufferDiscard) !void {
    var buffer = CircularBuffer(usize, 4, discard){};
    const nil: ?usize = null;

    // Empty
    try std.testing.expectEqual(@as(usize, 0), buffer.len);
    try std.testing.expectEqual(nil, buffer.pop());
    try std.testing.expectEqual(nil, buffer.peek_start());
    try std.testing.expectEqual(nil, buffer.get(0));
    try std.testing.expectEqual(nil, buffer.peek_end());

    // Push Some Values
    buffer.push(1);
    try std.testing.expectEqual(@as(usize, 1), buffer.len);
    try std.testing.expectEqual(@as(usize, 1), buffer.peek_start().?);
    try std.testing.expectEqual(@as(usize, 1), buffer.peek_end().?);
    buffer.push(2);
    try std.testing.expectEqual(@as(usize, 2), buffer.peek_end().?);
    buffer.push(3);
    try std.testing.expectEqual(@as(usize, 3), buffer.peek_end().?);
    try std.testing.expectEqual(@as(usize, 3), buffer.len);

    // Test get
    try std.testing.expectEqual(@as(usize, 1), buffer.get(0).?);
    try std.testing.expectEqual(@as(usize, 2), buffer.get(1).?);
    try std.testing.expectEqual(@as(usize, 3), buffer.get(2).?);
    try std.testing.expectEqual(nil, buffer.get(3));

    // Pop The Values
    try std.testing.expectEqual(@as(usize, 1), buffer.peek_start().?);
    try std.testing.expectEqual(@as(usize, 1), buffer.pop().?);
    try std.testing.expectEqual(@as(usize, 2), buffer.peek_start().?);
    try std.testing.expectEqual(@as(usize, 2), buffer.pop().?);
    try std.testing.expectEqual(@as(usize, 3), buffer.peek_start().?);
    try std.testing.expectEqual(@as(usize, 3), buffer.pop().?);

    // It's empty again
    try std.testing.expectEqual(@as(usize, 0), buffer.len);
    try std.testing.expectEqual(nil, buffer.pop());
    try std.testing.expectEqual(nil, buffer.peek_start());
    try std.testing.expectEqual(nil, buffer.get(0));
    try std.testing.expectEqual(nil, buffer.peek_end());

    // Fill it past capacity
    buffer.push(5);
    try std.testing.expectEqual(@as(usize, 5), buffer.peek_end().?);
    buffer.push(4);
    try std.testing.expectEqual(@as(usize, 4), buffer.peek_end().?);
    buffer.push(3);
    try std.testing.expectEqual(@as(usize, 3), buffer.peek_end().?);
    buffer.push(2);
    try std.testing.expectEqual(@as(usize, 2), buffer.peek_end().?);
    buffer.push(1);
    if (discard == .DiscardOldest) {
        try std.testing.expectEqual(@as(usize, 1), buffer.peek_end().?);
    }
    try std.testing.expectEqual(@as(usize, 4), buffer.len);

    // Test get
    var index: usize = 0;
    if (discard == .DiscardNewest) {
        try std.testing.expectEqual(@as(usize, 5), buffer.get(index).?);
        index += 1;
    }
    try std.testing.expectEqual(@as(usize, 4), buffer.get(index).?);
    index += 1;
    try std.testing.expectEqual(@as(usize, 3), buffer.get(index).?);
    index += 1;
    try std.testing.expectEqual(@as(usize, 2), buffer.get(index).?);
    index += 1;
    if (discard == .DiscardOldest) {
        try std.testing.expectEqual(@as(usize, 1), buffer.get(index).?);
        index += 1;
    }
    try std.testing.expectEqual(nil, buffer.get(index));

    // Pop The Values
    if (discard == .DiscardNewest) {
        try std.testing.expectEqual(@as(usize, 5), buffer.peek_start().?);
        try std.testing.expectEqual(@as(usize, 5), buffer.pop().?);
    }
    try std.testing.expectEqual(@as(usize, 4), buffer.peek_start().?);
    try std.testing.expectEqual(@as(usize, 4), buffer.pop().?);
    try std.testing.expectEqual(@as(usize, 3), buffer.pop().?);
    try std.testing.expectEqual(@as(usize, 2), buffer.peek_start().?);
    try std.testing.expectEqual(@as(usize, 2), buffer.pop().?);
    if (discard == .DiscardOldest) {
        try std.testing.expectEqual(@as(usize, 1), buffer.peek_start().?);
        try std.testing.expectEqual(@as(usize, 1), buffer.pop().?);
    }

    // It's empty yet again
    try std.testing.expectEqual(@as(usize, 0), buffer.len);
    try std.testing.expectEqual(nil, buffer.pop());
    try std.testing.expectEqual(nil, buffer.peek_start());
    try std.testing.expectEqual(nil, buffer.get(0));
    try std.testing.expectEqual(nil, buffer.peek_end());
}

test "CircularBuffer(.DiscardNewest)" {
    try test_circular_buffer(.DiscardNewest);
}

test "CircularBuffer(.DiscardOldest)" {
    try test_circular_buffer(.DiscardOldest);
}
