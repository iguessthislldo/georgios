// Interface to use the IBM PC Color Graphics Adapter (CGA)'s 80x25 text mode.
//
// TODO: Create abstract console interface.
//
// For Reference See:
//   "IBM Color/Graphics Monitor Adaptor"
//   https://en.wikipedia.org/wiki/VGA_text_mode
//   https://en.wikipedia.org/wiki/Code_page_437
//   https://wiki.osdev.org/Printing_to_Screen

const builtin = @import("builtin");

const utils = @import("utils");

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
const default_default_colors = combine_colors(Color.LightGrey, Color.Black);

var row: u32 = 0;
var column: u32 = 0;
var default_colors: u8 = default_default_colors;

var buffer: [*]u16 = undefined;

pub fn move_cursor(x: u32, y: u32) void {
    row = x;
    column = y;
    cursor(x, y);
}

pub fn reset_cursor() void {
    move_cursor(0, 0);
    show_cursor(true);
}

pub fn clear_screen() void {
    fill_screen(' ');
}

pub fn reset_attributes() void {
    default_colors = default_default_colors;
}

pub fn reset() void {
    reset_attributes();
    clear_screen();
    reset_cursor();
}

pub fn init() void {
    buffer = @intToPtr([*]u16, platform.kernel_to_virtual(0xB8000));
    reset();
}

pub fn set_colors(fg: Color, bg: Color) void {
    default_colors = combine_colors(fg, bg);
}

pub fn invert_colors() void {
    const n1 = @truncate(u4, default_colors);
    const n2 = @truncate(u4, default_colors >> 4);
    default_colors = @intCast(u8, n1) << 4 | n2;
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

pub fn show_cursor(show: bool) void {
    out8(command_port, set_cursor_shape_command);
    out8(data_port, if (show) 0 else 0x20); // Bit 5 Disables Cursor
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

pub fn newline() void {
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
        newline();
    }
    place_char(c, column, row);
    cursor(column + 1, row);
}

pub fn print_all_characters() void {
    reset();
    var i: u16 = 0;
    while (i < 256) {
        direct_print_char(@truncate(u8, i));
        if (i % 32 == 31) {
            newline();
        }
        i += 1;
    }
}

pub fn backspace() void {
    place_char(' ', column, row);
    cursor(column, row);
    if (column == 0 and row > 0) {
        column = width - 1;
        row -= 1;
    } else {
        column -= 1;
    }
}

// Print UTF8 Strings as Code Page 437 ========================================

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
    const bucket = code_point_437.hash_table[offset..offset +
        code_point_437.max_bucket_length];
    for (bucket[0..]) |entry| {
        const valid = @intCast(u8, entry >> 24);
        if (valid == 0) return null;
        const key = @truncate(u16, entry);
        const value = @truncate(u8, entry >> 16);
        if (key == c16) return value;
    }

    return null;
}

var utf32_buffer: [128]u32 = undefined;
var utf8_to_utf32 = utils.Utf8ToUtf32{.input = undefined, .buffer = utf32_buffer[0..]};

fn print_utf8_char(utf8_char: u8) void {
    utf8_to_utf32.input = @ptrCast([*]const u8, &utf8_char)[0..1];
    for (utf8_to_utf32.next() catch @panic("UTF-8 CGA Console Failure")) |char32| {
        direct_print_char(if (from_unicode(char32)) |c437| c437 else '?');
    }
}

var ansi_esc_processor = utils.AnsiEscProcessor{
    .print_char = print_utf8_char,
    .newline = newline,
    .backspace = backspace,
    .invert_colors = invert_colors,
    .reset_attributes = reset_attributes,
    .reset_terminal = reset,
    .move_cursor = move_cursor,
    .show_cursor = show_cursor,
};

pub fn print_char(byte: u8) void {
    ansi_esc_processor.feed_char(byte);
}
