// Unicode Utilities, Like Converting Character Encodings
//
// More Information:
//   https://en.wikipedia.org/wiki/UTF-8

const util = @import("util.zig");

const Error = error {
    InvalidUtf8,
} || util.Error;

const Utf8Iterator = struct {
    input: []const u8,
    pos: usize = 0,

    inline fn next_byte(self: *Utf8Iterator) Error!u8 {
        if (self.pos >= self.input.len) {
            return Error.OutOfBounds;
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

        var bytes: [4]u8 = undefined;
        bytes[0] = try self.next_byte();
        if (bytes[0] & 0b10000000 == 0) {
            return bytes[0];
        }
        const seqlen = @clz(u8, ~bytes[0]);
        if (seqlen < 2 or seqlen > 4) {
            return Error.InvalidUtf8;
        }
        var rv: u32 = bytes[0] & ((@as(u8, 1) << @intCast(u3, 7 - seqlen)) - 1);
        for (bytes[1..seqlen]) |*ptr, i| {
            ptr.* = try self.next_byte();
            if (ptr.* >> 6 != 0b10) {
                return Error.InvalidUtf8;
            }
            rv <<= 6;
            rv |= (ptr.* & 0b00111111);
        }
        return rv;
    }
};

pub const Utf8ToUtf32Result = struct {
    fit_in_output: []u32 = undefined,
    leftovers: []const u8,
};

pub fn utf8_to_utf32(input: []const u8, output: []u32) Error!Utf8ToUtf32Result {
    var it = Utf8Iterator{.input = input};
    var i: usize = 0;
    var loop = true;
    var leftovers: ?usize = null;
    while (loop) {
        const last_pos = it.pos;
        if (it.next()) |c| {
            if (i >= output.len) {
                leftovers = last_pos;
                break;
            }
            output[i] = c;
            i += 1;
        } else |e| switch (e) {
            Error.OutOfBounds => {
                loop = false;
            },
            else => {
                return e;
            },
        }
    }
    return Utf8ToUtf32Result{
        .fit_in_output=output[0..i],
        .leftovers=input[(if (leftovers == null) it.pos else leftovers.?)..]};
}

test "utf8_to_utf32" {
    const std = @import("std");

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

        const result = try utf8_to_utf32(input, buffer[0..]);
        std.testing.expectEqualSlices(u32, expected[0..], result.fit_in_output);
        std.testing.expectEqualSlices(u8, "", result.leftovers);
    }

    // One-Two Byte UTF-8 Code Units
    {
        const input: []const u8 = "Æðelstan";
        const expected = [_]u32 {
            0x000000c6, 0x000000f0, 0x00000065, 0x0000006c,
            0x00000073, 0x00000074, 0x00000061, 0x0000006e,
        };

        const result = try utf8_to_utf32(input, buffer[0..]);
        std.testing.expectEqualSlices(u32, expected[0..], result.fit_in_output);
        std.testing.expectEqualSlices(u8, "", result.leftovers);
    }

    // One-Four Byte UTF-8 Code Units
    {
        const input: []const u8 = "🍱 頂きます";
        const expected = [_]u32 {
            0x0001f371, 0x00000020, 0x00009802, 0x0000304d,
            0x0000307e, 0x00003059,
        };

        const result = try utf8_to_utf32(input, buffer[0..]);
        std.testing.expectEqualSlices(u32, expected[0..], result.fit_in_output);
        std.testing.expectEqualSlices(u8, "", result.leftovers);
    }

    // Output is Too Small, so There Are Leftovers
    {
        var too_small_buffer: [3]u32 = undefined;
        const input: []const u8 = "Hello";

        const expected_output1 = [_]u32 {0x00000048, 0x00000065, 0x0000006c};
        const result1 = try utf8_to_utf32(input, too_small_buffer[0..]);
        std.testing.expectEqualSlices(u32, expected_output1[0..], result1.fit_in_output);
        std.testing.expectEqualSlices(u8, input[too_small_buffer.len..], result1.leftovers);

        const expected_output2 = [_]u32 {0x0000006c, 0x0000006f};
        const result2 = try utf8_to_utf32(result1.leftovers, too_small_buffer[0..]);
        std.testing.expectEqualSlices(u32, expected_output2[0..], result2.fit_in_output);
        std.testing.expectEqualSlices(u8, "", result2.leftovers);
    }
}
