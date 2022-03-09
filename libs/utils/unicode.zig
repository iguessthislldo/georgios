// Unicode Utilities, Like Converting Character Encodings
//
// More Information:
//   https://en.wikipedia.org/wiki/UTF-8
//   The Unicode Standard.
//     For version 13.0, see volume 1 section 3.9 "Unicode Encoding Forms".
//     See Page 123 for the part on UTF-8

const std = @import("std");

const utils = @import("utils.zig");

pub const Error = error {
    InvalidUtf8,
    IncompleteUtf8,
} || utils.Error;

/// Possibly incomplete decode state to save if we don't have the entire
/// sequence at the moment.
pub const State = struct {
    byte_pos: u8 = 0,
    seqlen: u8 = 0,
    code_point: u32 = 0,
};

/// Low-level UTF-8 to UTF-32 converter. Returns individual code points.
pub const Utf8Iterator = struct {
    input: []const u8,
    pos: usize = 0,
    state: State = .{},

    fn next_byte(self: *Utf8Iterator, first_byte: bool) callconv(.Inline) Error!u8 {
        if (self.pos >= self.input.len) {
            return if (first_byte) Error.OutOfBounds else Error.IncompleteUtf8;
        }
        const byte = self.input[self.pos];
        self.pos += 1;
        return byte;
    }

    pub fn next(self: *Utf8Iterator) Error!u32 {
        // Valid UTF-8 code point sequences take these binary forms:
        //
        // 00000000 00000000 0aaaaaaa = 0aaaaaaa
        // 00000000 00000aaa aabbbbbb = 110aaaaa 10bbbbbb
        // 00000000 aaaabbbb bbcccccc = 1110aaaa 10bbbbbb 10cccccc
        // 000aaabb bbbbcccc ccdddddd = 11110aaa 10bbbbbb 10cccccc 10dddddd

        if (self.state.byte_pos == 0) {
            const first_byte = try self.next_byte(true);
            if (first_byte & 0b10000000 == 0) {
                return first_byte;
            }
            self.state.seqlen = @clz(u8, ~first_byte);
            if (self.state.seqlen < 2 or self.state.seqlen > 4) {
                return Error.InvalidUtf8;
            }
            self.state.code_point = first_byte &
                ((@as(u8, 1) << @intCast(u3, 7 - self.state.seqlen)) - 1);
            self.state.byte_pos = 1;
        }
        while (self.state.byte_pos < self.state.seqlen) {
            const byte = try self.next_byte(false);
            if (byte >> 6 != 0b10) {
                self.state.byte_pos = 0;
                return Error.InvalidUtf8;
            }
            self.state.code_point <<= 6;
            self.state.code_point |= (byte & 0b00111111);
            self.state.byte_pos += 1;
        }
        self.state.byte_pos = 0;
        return self.state.code_point;
    }
};

/// High-level UTF-8 to UTF-32 converter. Returns strings as large as the
/// buffer allows and there is input for.
pub const Utf8ToUtf32 = struct {
    input: []const u8,
    buffer: []u32,
    // Character to insert if there are errors. If null, then errors aren't
    // allowed.
    allow_errors: ?u32 = '?',
    state: State = .{},

    pub fn next(self: *Utf8ToUtf32) Error![]u32 {
        var it = Utf8Iterator{.input = self.input, .state = self.state};
        var i: usize = 0;
        var leftovers: ?usize = null;
        var save_state = false;
        var replace_char_leftover = false;
        while (true) {
            const last_pos = it.pos;
            if (it.next()) |c| {
                if (i >= self.buffer.len) {
                    leftovers = last_pos;
                    break;
                }
                self.buffer[i] = c;
                i += 1;
            } else |e| switch (e) {
                Error.OutOfBounds => {
                    break;
                },
                Error.IncompleteUtf8 => {
                    // Can't complete sequence. Save state so we can try to
                    // resume when we get more input.
                    save_state = true;
                    break;
                },
                Error.InvalidUtf8 => {
                    if (self.allow_errors) |replace_char| {
                        if (i >= self.buffer.len) {
                            replace_char_leftover = true;
                            break;
                        }
                        self.buffer[i] = replace_char;
                        i += 1;
                    } else {
                        return e;
                    }
                },
                else => {
                    return e;
                },
            }
        }
        if (replace_char_leftover) {
            self.input = @ptrCast([*]const u8, &self.allow_errors.?)[0..1];
        } else {
            self.input = self.input[(if (leftovers == null) it.pos else leftovers.?)..];
        }
        self.state = if (save_state) it.state else .{};
        return self.buffer[0..i];
    }
};

test "utf8_to_utf32" {
    var buffer: [128]u32 = undefined;

    // Use this Python function to generate expected u32 arrays:
    // def utf32_array(s):
    //     indent = '            '
    //     l = ['0x{:08x},'.format(ord(i)) for i in s]
    //     print('\n'.join([indent + ' '.join(l[i:i+4]) for i in range(0, len(l), 4)]))

    // One Byte UTF-8 Code Units
    {
        const input: []const u8 = "Hello";
        const expected = [_]u32 {
            0x00000048, 0x00000065, 0x0000006c, 0x0000006c,
            0x0000006f,
        };

        var utf8_to_utf32 = Utf8ToUtf32{.input = input, .buffer = buffer[0..]};
        try std.testing.expectEqualSlices(u32, expected[0..], try utf8_to_utf32.next());
        try std.testing.expectEqualSlices(u8, "", utf8_to_utf32.input);
    }

    // One-Two Byte UTF-8 Code Units
    {
        const input: []const u8 = "Æðelstan";
        const expected = [_]u32 {
            0x000000c6, 0x000000f0, 0x00000065, 0x0000006c,
            0x00000073, 0x00000074, 0x00000061, 0x0000006e,
        };

        var utf8_to_utf32 = Utf8ToUtf32{.input = input, .buffer = buffer[0..]};
        try std.testing.expectEqualSlices(u32, expected[0..], try utf8_to_utf32.next());
        try std.testing.expectEqualSlices(u8, "", utf8_to_utf32.input);
    }

    // One-Four Byte UTF-8 Code Units
    {
        const input: []const u8 = "🍱 頂きます";
        const expected = [_]u32 {
            0x0001f371, 0x00000020, 0x00009802, 0x0000304d,
            0x0000307e, 0x00003059,
        };

        var utf8_to_utf32 = Utf8ToUtf32{.input = input, .buffer = buffer[0..]};
        try std.testing.expectEqualSlices(u32, expected[0..], try utf8_to_utf32.next());
        try std.testing.expectEqualSlices(u8, "", utf8_to_utf32.input);
    }

    // Output is Too Small, so There Are Leftovers
    {
        var too_small_buffer: [3]u32 = undefined;
        const input: []const u8 = "Hello";
        var utf8_to_utf32 = Utf8ToUtf32{.input = input, .buffer = too_small_buffer[0..]};

        const expected_output1 = [_]u32 {0x00000048, 0x00000065, 0x0000006c};
        try std.testing.expectEqualSlices(u32, expected_output1[0..], try utf8_to_utf32.next());
        try std.testing.expectEqualSlices(u8, input[too_small_buffer.len..], utf8_to_utf32.input);

        const expected_output2 = [_]u32 {0x0000006c, 0x0000006f};
        try std.testing.expectEqualSlices(u32, expected_output2[0..], try utf8_to_utf32.next());
        try std.testing.expectEqualSlices(u8, "", utf8_to_utf32.input);
    }

    // Code point is broken up over multiple inputs.
    {
        const expected = [_]u32 {
            0x0001f371,
        };

        var utf8_to_utf32 = Utf8ToUtf32{.input = "\xf0\x9f", .buffer = buffer[0..]};
        try std.testing.expectEqualSlices(u32, expected[0..0], try utf8_to_utf32.next());
        try std.testing.expectEqualSlices(u8, "", utf8_to_utf32.input);
        utf8_to_utf32.input = "\x8d\xb1";
        try std.testing.expectEqualSlices(u32, expected[0..], try utf8_to_utf32.next());
        try std.testing.expectEqualSlices(u8, "", utf8_to_utf32.input);
    }

    // Code point is incomplete AND Buffer is too small.
    {
        var too_small_buffer: [2]u32 = undefined;

        const expected1 = [_]u32 {0x00000031, 0x00000032};
        var utf8_to_utf32 = Utf8ToUtf32{
            .input = "12\xf0\x9f\x8d", .buffer = too_small_buffer[0..]};
        try std.testing.expectEqualSlices(u32, expected1[0..], try utf8_to_utf32.next());
        try std.testing.expectEqualSlices(u8, "", utf8_to_utf32.input);

        const expected2 = [_]u32 {0x0001f371, 0x00000033};
        utf8_to_utf32.input = "\xb13";
        try std.testing.expectEqualSlices(u32, expected2[0..], try utf8_to_utf32.next());
        try std.testing.expectEqualSlices(u8, "", utf8_to_utf32.input);
    }

    // Errors can be overcome by default.
    {
        const expected = [_]u32 {
            0x00000048, 0x00000069, 0x0000003f, 0x0000003f,
            0x00000042, 0x00000079, 0x00000065,
        };

        // 0xf8 has an large number of leading ones, implies there are more
        // bytes in the sequence than are possible. It should be replaced by
        // '?'.
        // 0xc0 is a leading byte of a sequence like 0xf8, but the next byte
        // doesn't begin with 0b10 like it should. Both bytes should be
        // replaced by a single '?'.
        // NOTE: If the '!' byte began with 0b10, then we would accept it as
        // '!', though this would technically be invalid UTF-8 and is called an
        // overlong encoding.
        const input: []const u8 = "Hi\xf8\xc0!Bye";

        var utf8_to_utf32 = Utf8ToUtf32{.input = input, .buffer = buffer[0..]};
        try std.testing.expectEqualSlices(u32, expected[0..], try utf8_to_utf32.next());
        try std.testing.expectEqualSlices(u8, "", utf8_to_utf32.input);
    }

    // Errors can be overcome if there is no more room in the buffer
    {
        var too_small_buffer: [2]u32 = undefined;

        const input: []const u8 = "Hi\xf8";

        const expected1 = [_]u32 {0x00000048, 0x00000069};
        var utf8_to_utf32 = Utf8ToUtf32{.input = input, .buffer = too_small_buffer[0..]};
        try std.testing.expectEqualSlices(u32, expected1[0..], try utf8_to_utf32.next());
        try std.testing.expectEqualSlices(u8, "?", utf8_to_utf32.input);

        const expected2 = [_]u32 {0x0000003f};
        try std.testing.expectEqualSlices(u32, expected2[0..], try utf8_to_utf32.next());
        try std.testing.expectEqualSlices(u8, "", utf8_to_utf32.input);
    }

    // Decode can be strict
    {
        var utf8_to_utf32 = Utf8ToUtf32{
            .input = "Hi\xf8Bye", .buffer = buffer[0..], .allow_errors = null};
        try std.testing.expectError(Error.InvalidUtf8, utf8_to_utf32.next());
        utf8_to_utf32 = Utf8ToUtf32{
            .input = "Hi\xc0!Bye", .buffer = buffer[0..], .allow_errors = null};
        try std.testing.expectError(Error.InvalidUtf8, utf8_to_utf32.next());
    }
}
