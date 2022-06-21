// Interface to use the IBM PC Color Graphics Adapter (CGA)'s 80x25 text mode.
//
// For Reference See:
//   "IBM Color/Graphics Monitor Adaptor"
//   https://en.wikipedia.org/wiki/VGA_text_mode
//   https://en.wikipedia.org/wiki/Code_page_437
//   https://wiki.osdev.org/Printing_to_Screen

const kernel = @import("root").kernel;
const Console = kernel.Console;
const HexColor = Console.HexColor;

const util = @import("util.zig");
const out8 = util.out8;
const in8 = util.in8;
const platform = @import("platform.zig");
const code_point_437 = @import("code_point_437.zig");

const Color = enum(u4) {
    Black = 0,
    Blue = 1,
    Green = 2,
    Cyan = 3,
    Red = 4,
    Magenta = 5,
    Brown = 6,
    LightGray = 7,
    DarkGray = 8,
    LightBlue = 9,
    LightGreen = 10,
    LightCyan = 11,
    LightRed = 12,
    LightMagenta = 13,
    Yellow = 14,
    White = 15,

    var color_value: u16 = undefined;

    fn get_cga_color(ansi_color: HexColor) Color {
        return switch (ansi_color) {
            HexColor.White => .White,
            HexColor.LightGray => .LightGray,
            HexColor.DarkGray => .DarkGray,
            HexColor.Black => .Black,
            HexColor.Red => .Red,
            HexColor.Green => .Green,
            HexColor.Yellow => .Brown,
            HexColor.Blue => .Blue,
            HexColor.Magenta => .Magenta,
            HexColor.Cyan => .Cyan,
            HexColor.LightRed => .LightRed,
            HexColor.LightGreen => .LightGreen,
            HexColor.LightYellow => .Yellow,
            HexColor.LightBlue => .LightBlue,
            HexColor.LightMagenta => .LightMagenta,
            HexColor.LightCyan => .LightCyan,
        };
    }

    pub fn set(fg: HexColor, bg: HexColor) void {
        color_value = (@enumToInt(get_cga_color(fg)) |
            (@intCast(u16, @enumToInt(get_cga_color(bg))) << 4)) << 8;
    }

    pub fn char_value(c: u8) callconv(.Inline) u16 {
        return @intCast(u16, c) | color_value;
    }
};

const command_port: u16 = 0x03D4;
const data_port: u16 = 0x03D5;
const high_byte_command: u8 = 14;
const low_byte_command: u8 = 15;
const set_cursor_shape_command: u8 = 0x0a;
const default_fg_color = HexColor.White;
const default_bg_color = HexColor.Black;

var fg_color = default_fg_color;
var bg_color = default_bg_color;
var buffer: [*]u16 = undefined;
pub var console = Console{
    .place_impl = place_impl,
    .scroll_impl = scroll_impl,
    .set_hex_color_impl = set_hex_color_impl,
    .get_hex_color_impl = get_hex_color_impl,
    .reset_attributes_impl = reset_attributes_impl,
    .move_cursor_impl = move_cursor_impl,
    .show_cursor_impl = show_cursor_impl,
    .clear_screen_impl = clear_screen_impl,
};

pub fn init() void {
    buffer = @intToPtr([*]u16, platform.kernel_to_virtual(0xB8000));
    console.init(80, 25);
}

fn place_impl(c: *Console, utf32_value: u32, row: u32, col: u32) void {
    const cp437_value = if (from_unicode(utf32_value)) |cp437| cp437 else '?';
    const index: u32 = (row *% c.width) +% col;
    buffer[index] = Color.char_value(cp437_value);
}

pub fn set_hex_color_impl(c: *Console, color: HexColor, layer: Console.Layer) void {
    _ = c;
    if (layer == .Foreground) {
        fg_color = color;
    } else {
        bg_color = color;
    }
    Color.set(fg_color, bg_color);
}

pub fn get_hex_color_impl(c: *Console, layer: Console.Layer) HexColor {
    _ = c;
    return if (layer == .Foreground) fg_color else bg_color;
}

pub fn reset_attributes_impl(c: *Console) void {
    c.set_hex_colors(default_fg_color, default_bg_color);
}

pub fn clear_screen_impl(c: *Console) void {
    var row: u32 = 0;
    while (row < c.height) : (row +%= 1) {
        var col: u32 = 0;
        while (col < c.width) : (col +%= 1) {
            c.place(' ', row, col);
        }
    }
}

pub fn move_cursor_impl(c: *Console, row: u32, col: u32) void {
    const index: u32 = (row *% c.width) +% col;
    out8(command_port, high_byte_command);
    out8(data_port, @intCast(u8, (index >> 8) & 0xFF));
    out8(command_port, low_byte_command);
    out8(data_port, @intCast(u8, index & 0xFF));
}

pub fn show_cursor_impl(c: *Console, show: bool) void {
    _ = c;
    out8(command_port, set_cursor_shape_command);
    out8(data_port, if (show) 0 else 0x20); // Bit 5 Disables Cursor
}

pub fn scroll_impl(c: *Console) void {
    var y: u32 = 1;
    while (y < c.height) : (y +%= 1) {
        var x: u32 = 0;
        while (x < c.width) : (x +%= 1) {
            const src: u32 = (y *% c.width) +% x;
            const dest: u32 = ((y - 1) *% c.width) +% x;
            buffer[dest] = buffer[src];
        }
    }
    var x: u32 = 0;
    while (x < c.width) : (x +%= 1) {
        c.place(' ', c.height - 1, x);
    }
}

pub fn print_all_characters() void {
    console.reset_terminal();
    var i: u16 = 0;
    while (i < 256) {
        console.print_char(@truncate(u8, i));
        if (i % 32 == 31) {
            console.newline();
        }
        i += 1;
    }
}

/// Convert UTF-32 to Code Page 437
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
