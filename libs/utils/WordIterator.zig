const Self = @This();

const std = @import("std");

const utils = @import("utils.zig");
const Error = utils.Error;

input: []const u8,
buffer: ?[]u8 = null,
start: usize = 0,
sep: u8 = ' ',
quote: ?u8 = null,
escape: u8 = '\\',
escaped: bool = undefined,
quoted: bool = undefined,

fn process_char(self: *Self, c: u8) bool {
    if (self.quote) |quote| {
        if (self.escaped) {
            self.escaped = false;
        } else if (c == self.escape) {
            self.escaped = true;
            return false; // Don't keep escape char
        } else if (c == quote) {
            self.quoted = !self.quoted;
            return false; // Don't keep quote char
        }
    }
    return true;
}

/// Allow caller to process words as they want, then they can call
/// postprocess to clean up remaining quotes and escapes.
pub fn next_unprocessed(self: *Self) ?[]const u8 {
    var this_start = self.start;
    var end = self.input.len;
    if (this_start >= end) return null;
    // Skip past any leading seperators
    for (self.input[this_start..]) |c| {
        if (c != self.sep) {
            break;
        }
        this_start += 1;
    }
    self.escaped = false;
    self.quoted = false;
    for (self.input[this_start..]) |c, i| {
        _ = self.process_char(c);
        if (!(self.escaped or self.quoted) and c == self.sep) {
            end = this_start + i;
            break;
        }
    }
    self.start = end;
    if (this_start >= end) return null;
    return self.input[this_start..end];
}

pub fn postprocess(self: *Self, word: []const u8) Error![]const u8 {
    if (self.quote == null or self.buffer == null) return word;
    const buffer = self.buffer.?;
    self.escaped = false;
    self.quoted = false;
    var i: usize = 0;
    for (word) |c| {
        if (self.process_char(c)) {
            if (i >= buffer.len) return Error.NotEnoughDestination;
            buffer[i] = c;
            i += 1;
        }
    }
    return buffer[0..i];
}

pub fn next(self: *Self) Error!?[]const u8 {
    if (self.next_unprocessed()) |word| {
        return try self.postprocess(word);
    }
    return null;
}

fn test_word_iterator(word_it: *Self, expected: ?[]const u8) !void {
    const word_maybe = try word_it.next();
    try std.testing.expect((expected == null) == (word_maybe == null));
    if (word_maybe) |word| {
        try std.testing.expectEqualStrings(expected.?, word);
    }
}

var test_buffer: [32]u8 = undefined;

test "WordIterator simple" {
    {
        var word_it = Self{.input = "", .buffer = test_buffer[0..]};
        try test_word_iterator(&word_it, null);
    }

    {
        var word_it = Self{.input = "ABC"};
        try test_word_iterator(&word_it, "ABC");
        try test_word_iterator(&word_it, null);
    }

    {
        var word_it = Self{.input = "A BCD E", .buffer = test_buffer[0..]};
        try test_word_iterator(&word_it, "A");
        try test_word_iterator(&word_it, "BCD");
        try test_word_iterator(&word_it, "E");
        try test_word_iterator(&word_it, null);
    }

    {
        var word_it = Self{.input = " A BCD E   "};
        try test_word_iterator(&word_it, "A");
        try test_word_iterator(&word_it, "BCD");
        try test_word_iterator(&word_it, "E");
        try test_word_iterator(&word_it, null);
    }
}

test "WordIterator complex with no postprocess" {
    var word_it = Self{
        .quote = '\'',
        .input = " '' 'A' ' ' 'B'' ' \\C \\' ' EF\\' ' "
    };
    try test_word_iterator(&word_it, "''");
    try test_word_iterator(&word_it, "'A'");
    try test_word_iterator(&word_it, "' '");
    try test_word_iterator(&word_it, "'B'' '");
    try test_word_iterator(&word_it, "\\C");
    try test_word_iterator(&word_it, "\\'");
    try test_word_iterator(&word_it, "' EF\\' '");
    try test_word_iterator(&word_it, null);
}

test "WordIterator complex with postprocess" {
    var word_it = Self{
        .quote = '\'',
        .input = "  '' 'A' ' ' 'B'' ' \\C \\' ' EF\\' ' ",
        .buffer = test_buffer[0..],
    };
    try test_word_iterator(&word_it, "");
    try test_word_iterator(&word_it, "A");
    try test_word_iterator(&word_it, " ");
    try test_word_iterator(&word_it, "B ");
    try test_word_iterator(&word_it, "C");
    try test_word_iterator(&word_it, "'");
    try test_word_iterator(&word_it, " EF' ");
    try test_word_iterator(&word_it, null);
}
