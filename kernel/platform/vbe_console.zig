const kernel = @import("root").kernel;
const Console = kernel.Console;
const HexColor = Console.HexColor;

const platform = @import("platform.zig");
const vbe = platform.vbe;
const font = vbe.font;

pub fn color_value_from_hex_color(hex_color: HexColor) u32 {
    return switch (hex_color) {
        HexColor.White => 0x00e8e6e3,
        HexColor.LightGray => 0x00D0CFCC,
        HexColor.DarkGray => 0x005E5C64,
        HexColor.Black => 0x00171421,
        HexColor.Red => 0x00C01C28,
        HexColor.Green => 0x0026A269,
        HexColor.Yellow => 0x00A2734C,
        HexColor.Blue => 0x0012488B,
        HexColor.Magenta => 0x00A347BA,
        HexColor.Cyan => 0x002AA1B3,
        HexColor.LightRed => 0x00F66151,
        HexColor.LightGreen => 0x0033DA7A,
        HexColor.LightYellow => 0x00E9AD0C,
        HexColor.LightBlue => 0x002A7BDE,
        HexColor.LightMagenta => 0x00C061CB,
        HexColor.LightCyan => 0x0033C7DE,
    };
}

const default_fg_color = HexColor.Black;
const default_fg_color_value = color_value_from_hex_color(default_fg_color);
const default_bg_color = HexColor.White;
const default_bg_color_value = color_value_from_hex_color(default_bg_color);

var fg_color: HexColor = undefined;
var bg_color: HexColor = undefined;
var fg_color_value: u32 = undefined;
var bg_color_value: u32 = undefined;
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
var text_buffer: [][]u8 = undefined;

pub fn init(screen_width: u32, screen_height: u32) void {
    console.init(screen_width / font.width , screen_height / font.height);
    text_buffer = kernel.alloc.alloc_array([]u8, console.height) catch @panic("vbe_console text_buffer");
    for (text_buffer) |*row| {
        row.* = kernel.alloc.alloc_array(u8, console.width) catch @panic("vbe_console text_buffer");
    }
    clear_screen_impl(&console);
}

fn place_impl_no_flush(c: *Console, utf32_value: u32, row: u32, col: u32) void {
    _ = c;
    _ = utf32_value;
    const char = if (utf32_value >= ' ' and utf32_value <= 0x7e) @truncate(u8, utf32_value) else '?';
    text_buffer[row][col] = char;
    const x = col * font.width;
    const y = row * font.height;
    _ = vbe.draw_glyph(x, y, char, fg_color_value, bg_color_value);
}

fn place_impl(c: *Console, utf32_value: u32, row: u32, col: u32) void {
    place_impl_no_flush(c, utf32_value, row, col);
    vbe.flush_buffer();
}

pub fn set_hex_color_impl(c: *Console, color: HexColor, layer: Console.Layer) void {
    _ = c;
    if (layer == .Foreground) {
        fg_color = color;
        fg_color_value = color_value_from_hex_color(color);
    } else {
        bg_color = color;
        bg_color_value = color_value_from_hex_color(color);
    }
}

pub fn get_hex_color_impl(c: *Console, layer: Console.Layer) HexColor {
    _ = c;
    return if (layer == .Foreground) fg_color else bg_color;
}

pub fn reset_attributes_impl(c: *Console) void {
    c.set_hex_colors(default_fg_color, default_bg_color);
}

pub fn clear_screen_impl(c: *Console) void {
    _ = c;
    // vbe.fill_buffer(0xe8e6e3);
    vbe.fill_buffer(default_bg_color_value);
    for (text_buffer) |*row| {
        for (row.*) |*char| {
            char.* = 0;
        }
    }
    vbe.flush_buffer();
}

pub fn move_cursor_impl(c: *Console, row: u32, col: u32) void {
    _ = c;
    _ = row;
    _ = col;
}

pub fn show_cursor_impl(c: *Console, show: bool) void {
    _ = c;
    _ = show;
}

fn get_text_buffer(row: u32, col: u32) u8 {
    return text_buffer[row][col];
}

pub fn scroll_impl(c: *Console) void {
    _ = c;
    // vbe.fill_buffer(0xe8e6e3);
    vbe.fill_buffer(default_bg_color_value);
    // TODO: Like all the VBE operations, this is really really slow
    for (text_buffer[0..text_buffer.len - 1]) |*row, row_i| {
        for (row.*) |*char, col_i| {
            char.* = get_text_buffer(row_i + 1, col_i);
            if (char.* > 0) place_impl_no_flush(c, char.*, row_i, col_i);
        }
    }
    for (text_buffer[text_buffer.len - 1]) |*char| {
        char.* = 0;
    }
    vbe.flush_buffer();
}
