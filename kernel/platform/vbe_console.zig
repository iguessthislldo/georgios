const utils = @import("utils");

const kernel = @import("root").kernel;
const Console = kernel.Console;
const HexColor = Console.HexColor;
const BitmapFont = kernel.BitmapFont;

const platform = @import("platform.zig");
const vbe = platform.vbe;
const U32Box = vbe.U32Box;

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

var font: *const BitmapFont = undefined;
var glyph_width: usize = undefined;
var glyph_height: usize = undefined;
var fg_color: HexColor = undefined;
var bg_color: HexColor = undefined;
var fg_color_value: u32 = undefined;
var bg_color_value: u32 = undefined;
var scroll_count: u32 = 0;
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

pub fn init(screen_width: u32, screen_height: u32, bitmap_font: *const BitmapFont) void {
    font = bitmap_font;
    glyph_width = font.bdf_font.bounds.size.x;
    glyph_height = font.bdf_font.bounds.size.y;
    console.init(screen_width / glyph_width, screen_height / glyph_height);
    clear_screen_impl(&console);
}

fn place_impl_no_flush(c: *Console, utf32_value: u32, row: u32, col: u32) U32Box {
    _ = c;
    const x = col * glyph_width;
    const y = row * glyph_height;
    vbe.draw_glyph(font, x, y, utf32_value, fg_color_value, bg_color_value);
    return .{.pos = .{.x = x, .y = y}, .size = .{.x = glyph_width, .y = glyph_height}};
}

fn place_impl(c: *Console, utf32_value: u32, row: u32, col: u32) void {
    vbe.flush_buffer_area(place_impl_no_flush(c, utf32_value, row, col));
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
    scroll_count = 0;
    c.set_hex_colors(default_fg_color, default_bg_color);
}

pub fn clear_screen_impl(c: *Console) void {
    _ = c;
    vbe.fill_buffer(default_bg_color_value);
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

pub fn scroll_impl(c: *Console) void {
    _ = c;
    scroll_count += 1;
    vbe.scroll_buffer(glyph_height, default_bg_color_value);
    vbe.flush_buffer();
}

pub fn get_info(last_scroll_count: *u32, size: *utils.U32Point, pos: *utils.U32Point, glyph_size: *utils.U32Point) void {
    last_scroll_count.* = scroll_count;
    scroll_count = 0;
    size.* = .{.x = console.width, .y = console.height};
    pos.* = .{.x = console.column, .y = console.row};
    const gs = font.bdf_font.bounds.size;
    glyph_size.* = .{.x = gs.x, .y = gs.y};
}
