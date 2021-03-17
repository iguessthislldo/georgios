// Interface to use the IBM PC Color Graphics Adapter (CGA)'s 80x25 text mode.

const builtin = @import("builtin");

const unicode = @import("../unicode.zig");

const util = @import("util.zig");
const out8 = util.out8;
const in8 = util.in8;
const platform = @import("platform.zig");
const code_point_437 = @import("code_point_437.zig");

pub const Color = enum {
    Black = 0,
    Blue = 1,
    Green = 2,
    Cyan = 3,
    Red = 4,
    Magenta = 5,
    Brown = 6,
    LightGrey = 7,
    DarkGrey = 8,
    LightBlue = 9,
    LightGreen = 10,
    LightCyan = 11,
    LightRed = 12,
    LightMagenta = 13,
    LightBrown = 14,
    White = 15,
};

inline fn combine_colors(fg: Color, bg: Color) u8 {
    return @enumToInt(fg) | (@intCast(u8, @enumToInt(bg)) << 4);
}

inline fn colored_char(c: u8, colors: u8) u16 {
    return @intCast(u16, c) | (@intCast(u16, colors) << 8);
}

const width: u32 = 80;
const height: u32 = 25;
const command_port: u16 = 0x03D4;
const data_port: u16 = 0x03D5;
const high_byte_command: u8 = 14;
const low_byte_command: u8 = 15;
const set_cursor_shape_command: u8 = 0x0a;

var row: u32 = 0;
var column: u32 = 0;
var default_colors: u8 = combine_colors(Color.LightGrey, Color.Black);

var buffer: [*]u16 = undefined;

pub fn new_page() void {
    row = 0;
    column = 0;
    fill_screen(' ');
    cursor(0, 0);
}

pub fn initialize() void {
    buffer = @intToPtr([*]u16, platform.kernel_to_virtual(0xB8000));
    new_page();
}

pub fn set_colors(fg: Color, bg: Color) void {
    default_colors = combine_colors(fg, bg);
}

pub fn place_char(c: u8, x: u32, y: u32) void {
    const index: u32 = (y *% width) +% x;
    buffer[index] = colored_char(c, default_colors);
}

pub fn fill_screen(c: u8) void {
    var y: u32 = 0;
    while (y < height) : (y +%= 1) {
        var x: u32 = 0;
        while (x < width) : (x +%= 1) {
            place_char(c, x, y);
        }
    }
}

pub fn cursor(x: u32, y: u32) void {
    const index: u32 = (y *% width) +% x;
    out8(command_port, high_byte_command);
    out8(data_port, @intCast(u8, (index >> 8) & 0xFF));
    out8(command_port, low_byte_command);
    out8(data_port, @intCast(u8, index & 0xFF));
}

pub fn disable_cursor() void {
    out8(command_port, set_cursor_shape_command);
    out8(data_port, 0x20); // Bit 5 Disables Cursor
}

pub fn scroll() void {
    var y: u32 = 1;
    while (y < height) : (y +%= 1) {
        var x: u32 = 0;
        while (x < width) : (x +%= 1) {
            const src: u32 = (y *% width) +% x;
            const dest: u32 = ((y-1) *% width) +% x;
            buffer[dest] = buffer[src];
        }
    }
    var x: u32 = 0;
    while (x < width) : (x +%= 1) {
        place_char(' ', x, height-1);
    }
}

pub fn new_line() void {
    if (row == (height - 1)) {
        scroll();
    } else {
        row += 1;
    }
    column = 0;
    cursor(1, row);
}

pub fn direct_print_char(c: u8) void {
    column += 1;
    if (column == width) {
        new_line();
    }
    place_char(c, column, row);
    cursor(column + 1, row);
}

pub fn print_char(c: u8) void {
    if (c == '\n') {
        new_line();
    } else {
        direct_print_char(c);
    }
}

pub fn print_all_characters() void {
    new_page();
    var i: u16 = 0;
    while (i < 256) {
        direct_print_char(@truncate(u8, i));
        if (i % 32 == 31) {
            new_line();
        }
        i += 1;
    }
}

pub fn from_unicode(c: u32) ?u8 {
    // Code Page 437 Doesn't Have Any Points Past 2^16
    if (c > 0xFFFF) return null;
    const c16 = @intCast(u16, c);

    // Check a few contiguous ranges. The main one is Printable ASCII.
    if (code_point_437.contiguous_ranges(c16)) |c8| return c8;

    // Else check the hash table
    const hash = c16 % code_point_437.bucket_count;
    if (hash > code_point_437.max_hash_used) return null;
    const offset = hash * code_point_437.max_bucket_length;
    const bucket = code_point_437.hash_table[offset..offset + code_point_437.max_bucket_length];
    for (bucket[0..]) |entry| {
        const valid = @intCast(u8, entry >> 24);
        if (valid == 0) return null;
        const key = @truncate(u16, entry);
        const value = @truncate(u8, entry >> 16);
        if (key == c16) return value;
    }

    return null;
}

pub fn print_utf8_string(s: []const u8) void {
    var b: [128]u32 = undefined;
    var r = unicode.Utf8ToUtf32Result{.leftovers=s[0..]};
    while (true) {
        r = unicode.utf8_to_utf32(r.leftovers, b[0..])
            catch @panic("UTF-8 CGA Console Failure");
        for (r.fit_in_output[0..]) |i| {
            if (i == '\n') {
                new_line();
            } else {
                direct_print_char(if (from_unicode(i)) |c437| c437 else '?');
            }
        }
        if (r.leftovers.len == 0) break;
    }
}
