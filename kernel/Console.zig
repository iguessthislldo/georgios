const Self = @This();

const utils = @import("utils");
const Ansi = utils.AnsiEscProcessor;

pub const HexColor = Ansi.HexColor;
pub const Layer = Ansi.Layer;

row: u32 = undefined,
column: u32 = undefined,
width: u32 = undefined,
height: u32 = undefined,
ansi: Ansi = undefined,
utf32_buffer: [128]u32 = undefined,
utf8_to_utf32: utils.Utf8ToUtf32 = undefined,

place_impl: fn(console: *Self, utf32_value: u32, row: u32, col: u32) void,
scroll_impl: fn(console: *Self) void,
set_hex_color_impl: fn(console: *Self, color: HexColor, layer: Layer) void,
get_hex_color_impl: fn(console: *Self, layer: Layer) HexColor,
reset_attributes_impl: fn(console: *Self) void,
move_cursor_impl: fn(console: *Self, row: u32, col: u32) void,
show_cursor_impl: fn(console: *Self, show: bool) void,
clear_screen_impl: fn(console: *Self) void,

pub fn init(self: *Self, width: u32, height: u32) void {
    self.width = width;
    self.height = height;
    self.ansi = .{
      .print_char = ansi_print_char,
      .newline = ansi_newline,
      .backspace = ansi_backspace,
      .hex_color = ansi_hex_color,
      .invert_colors = ansi_invert_colors,
      .reset_attributes = ansi_reset_attributes,
      .reset_terminal = ansi_reset_terminal,
      .move_cursor = ansi_move_cursor,
      .show_cursor = ansi_show_cursor,
    };
    self.utf8_to_utf32 = .{.input = undefined, .buffer = self.utf32_buffer[0..]};
    self.reset_terminal();
}

/// Takes a UTF8/ANSI escape code byte
pub fn print(self: *Self, byte: u8) void {
    self.ansi.feed_char(byte);
}

pub fn print_utf8(self: *Self, utf8_value: u8) void {
    self.utf8_to_utf32.input = @ptrCast([*]const u8, &utf8_value)[0..1];
    // TODO: Shouldn't crash the kernel just because we got an invalid UTF8 byte.
    for (self.utf8_to_utf32.next() catch @panic("Console UTF-8 Failure")) |utf32_value| {
        self.print_utf32(utf32_value);
    }
}

pub fn print_utf32(self: *Self, utf32_value: u32) void {
    if ((self.column + 1) > self.width) {
        self.newline();
    }
    self.place(utf32_value, self.row, self.column);
    self.move_cursor(self.row, self.column + 1);
}

pub fn place(self: *Self, utf32_value: u32, row: u32, col: u32) void {
    self.place_impl(self, utf32_value, row, col);
}

pub fn ansi_print_char(ansi: *Ansi, char: u8) void {
    const self = @fieldParentPtr(Self, "ansi", ansi);
    self.print_utf8(char);
}

pub fn newline(self: *Self) void {
    if (self.row == (self.height - 1)) {
        self.scroll_impl(self);
    } else {
        self.row += 1;
    }
    self.move_cursor(self.row, 0);
}

pub fn ansi_newline(ansi: *Ansi) void {
    const self = @fieldParentPtr(Self, "ansi", ansi);
    self.newline();
}

pub fn backspace(self: *Self) void {
    var row = self.row;
    var col = self.column;
    if (col == 0 and row > 0) {
        col = self.width - 1;
        row -= 1;
    } else {
        col -= 1;
    }
    self.move_cursor(row, col);
    self.place(' ', self.row, self.column);
}

pub fn ansi_backspace(ansi: *Ansi) void {
    const self = @fieldParentPtr(Self, "ansi", ansi);
    self.backspace();
}

pub fn set_hex_color(self: *Self, color: HexColor, layer: Layer) void {
    self.set_hex_color_impl(self, color, layer);
}

pub fn ansi_hex_color(ansi: *Ansi, color: HexColor, layer: Layer) void {
    const self = @fieldParentPtr(Self, "ansi", ansi);
    self.set_hex_color(color, layer);
}

pub fn set_hex_colors(self: *Self, fg: HexColor, bg: HexColor) void {
    self.set_hex_color(fg, .Foreground);
    self.set_hex_color(bg, .Background);
}

pub fn get_hex_color(self: *Self, layer: Layer) HexColor {
    return self.get_hex_color_impl(self, layer);
}

pub fn invert_colors(self: *Self) void {
    const fg = self.get_hex_color(.Foreground);
    const bg = self.get_hex_color(.Background);
    self.set_hex_colors(bg, fg);
}

pub fn ansi_invert_colors(ansi: *Ansi) void {
    const self = @fieldParentPtr(Self, "ansi", ansi);
    self.invert_colors();
}

pub fn reset_attributes(self: *Self) void {
    self.reset_attributes_impl(self);
}

pub fn ansi_reset_attributes(ansi: *Ansi) void {
    const self = @fieldParentPtr(Self, "ansi", ansi);
    self.reset_attributes();
}

pub fn move_cursor(self: *Self, row: u32, col: u32) void {
    self.row = row;
    self.column = col;
    self.move_cursor_impl(self, row, col);
}

pub fn ansi_move_cursor(ansi: *Ansi, row: u32, col: u32) void {
    const self = @fieldParentPtr(Self, "ansi", ansi);
    self.move_cursor(row, col);
}

pub fn show_cursor(self: *Self, show: bool) void {
    self.show_cursor_impl(self, show);
}

pub fn ansi_show_cursor(ansi: *Ansi, show: bool) void {
    const self = @fieldParentPtr(Self, "ansi", ansi);
    self.show_cursor(show);
}

pub fn reset_cursor(self: *Self) void {
    self.move_cursor(0, 0);
    self.show_cursor(true);
}

pub fn clear_screen(self: *Self) void {
    self.clear_screen_impl(self);
}

pub fn reset_terminal(self: *Self) void {
    self.reset_attributes();
    self.clear_screen_impl(self);
    self.reset_cursor();
}

pub fn ansi_reset_terminal(ansi: *Ansi) void {
    const self = @fieldParentPtr(Self, "ansi", ansi);
    self.reset_terminal();
}
