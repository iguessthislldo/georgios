// ANSI Escape Code Sequence Processor ========================================
//
// Takes a stream of bytes and interprets it if it responds to recognized ANSI
// escape codes by invoking callbacks.
//
// More Info:
//   https://en.wikipedia.org/wiki/ANSI_escape_code
//   https://vt100.net/docs/vt100-ug/chapter3.html
//   https://gist.github.com/fnky/458719343aabd01cfb17a3a4f7296797
// ============================================================================

const std = @import("std");

const Self = @This();

pub const HexColor = enum(u4) {
    White = 15, // Spec name is bright white
    LightGray = 7, // Spec name is white
    DarkGray = 8, // Spec name is bright black
    Black = 0,
    Red = 1,
    Green = 2,
    Yellow = 3,
    Blue = 4,
    Magenta = 5,
    Cyan = 6,
    LightRed = 9,
    LightGreen = 10,
    LightYellow = 11,
    LightBlue = 12,
    LightMagenta = 13,
    LightCyan = 14,
};

pub const Layer = enum {
    Foreground,
    Background,
};

const State = enum {
    Unescaped,
    Escaped,
    Csi,
};

print_char: ?fn(self: *Self, char: u8) void = null,
hex_color: ?fn(self: *Self, color: HexColor, layer: Layer) void = null,
invert_colors: ?fn(self: *Self) void = null,
backspace: ?fn(self: *Self) void = null,
newline: ?fn(self: *Self) void = null,
use_default_color: ?fn(self: *Self, layer: Layer) void = null,
reset_attributes: ?fn(self: *Self) void = null,
reset_terminal: ?fn(self: *Self) void = null,
move_cursor: ?fn(self: *Self, r: usize, c: usize) void = null,
show_cursor: ?fn(self: *Self, show: bool) void = null,

state: State = .Unescaped,
saved: [64]u8 = undefined,
parameter_start: ?usize = null,
parameters: [16]usize = undefined,
parameter_count: usize = 0,
saved_so_far: usize = 0,
malformed_sequences: usize = 0,

fn process_parameter(self: *Self) bool {
    var parameter: ?u16 = null;
    if (self.parameter_start) |start| {
        const parameter_str = self.saved[start..self.saved_so_far];
        parameter = std.fmt.parseUnsigned(u16, parameter_str, 10) catch null;
        self.parameter_start = null;
    } else { // empty parameter
        parameter = 0;
    }
    if (parameter) |p| {
        // std.debug.print("Parameter: {}\n", .{p});
        if (self.parameter_count < self.parameters.len) {
            self.parameters[self.parameter_count] = p;
            self.parameter_count += 1;
        } else {
            return true;
        }
    }
    return parameter == null;
}

fn select_graphic_rendition(self: *Self) void {
    var i: usize = 0;
    while (i < self.parameter_count) {
        const p = self.parameters[i];
        // std.debug.print("SGR: {}\n", .{p});
        switch (p) {
            0 => if (self.reset_attributes) |reset_attributes| reset_attributes(self),
            7 => if (self.invert_colors) |invert_colors| invert_colors(self),
            30...37 => if (self.hex_color) |hex_color|
                hex_color(self, @intToEnum(HexColor, p - 30), .Foreground),
            39 => if (self.use_default_color) |use_default_color|
                use_default_color(self, .Foreground),
            40...47 => if (self.hex_color) |hex_color|
                hex_color(self, @intToEnum(HexColor, p - 40), .Background),
            49 => if (self.use_default_color) |use_default_color|
                use_default_color(self, .Background),
            90...97 => if (self.hex_color) |hex_color|
                hex_color(self, @intToEnum(HexColor, p - 82), .Foreground),
            100...107 => if (self.hex_color) |hex_color|
                hex_color(self, @intToEnum(HexColor, p - 92), .Background),
            else => {},
        }
        i += 1;
    }
}

fn process_move_cursor(self: *Self) void {
    var column: usize = 0;
    if (self.parameter_count > 1) {
        column = self.parameters[1];
    }
    var row: usize = 0;
    if (self.parameter_count > 0) {
        row = self.parameters[0];
    }
    if (self.move_cursor) |move_cursor| {
        move_cursor(self, row, column);
    }
}

pub fn feed_char(self: *Self, char: u8) void {
    self.saved[self.saved_so_far] = char;

    // std.debug.print("feed_char {c}\n", .{char});
    var abort = false;
    var reset = false;
    switch (self.state) {
        .Unescaped => {
            reset = true;
            switch (char) {
                0x08 => if (self.backspace) |backspace| backspace(self),

                '\n' => {
                    if (self.newline) |newline| {
                        newline(self);
                    } else if (self.print_char) |print_char| {
                        print_char(self, char);
                    }
                },

                0x1b => {
                    self.state = .Escaped;
                    reset = false;
                },

                else => {
                    if (self.print_char) |print_char| {
                        print_char(self, char);
                    }
                },
            }
        },

        .Escaped => {
            switch (char) {
                '[' => self.state = .Csi,

                'c' => {
                    if (self.reset_terminal) |reset_terminal| {
                        reset_terminal(self);
                    }
                    reset = true;
                },

                else => abort = true,
            }
        },

        .Csi => {
            switch (char) {
                '0'...'9' => {
                    if (self.parameter_start == null) {
                        self.parameter_start = self.saved_so_far;
                    }
                },

                '?' => {
                    // TODO
                    // private = true;
                },

                ';' => {
                    abort = self.process_parameter();
                },

                'm' => {
                    abort = self.process_parameter();
                    if (!abort) {
                        self.select_graphic_rendition();
                        reset = true;
                    }
                },

                'H' => {
                    abort = self.process_parameter();
                    if (!abort) {
                        self.process_move_cursor();
                        reset = true;
                    }
                },

                'l' => {
                    // if (self.parameter_count == 1 and self.parameters[0] == 25) {
                        if (self.show_cursor) |show_cursor| {
                            show_cursor(self, false);
                        }
                        reset = true;
                    // } else {
                    //     abort = true;
                    // }
                },

                else => abort = true,
            }
        },
    }

    self.saved_so_far += 1;

    reset = reset or abort;

    // If we're not gonna reset, abort if we're gonna be outa room on the
    // next character.
    if (!reset and self.saved_so_far == self.saved.len) {
        abort = true;
    }

    if (abort) {
        // std.debug.print("Abort\n", .{});
        if (self.print_char) |print_char| {
            // Dump the malformed sequence. Seems to be what Gnome's terminal does.
            for (self.saved[0..self.saved_so_far]) |c| {
                print_char(self, c);
            }
        }
        self.malformed_sequences += 1;
    }

    if (reset) {
        self.parameter_count = 0;
        self.state = .Unescaped;
        self.saved_so_far = 0;
        self.parameter_start = null;
    }

    // std.debug.print("state {s}\n", .{@tagName(self.state)});
}

pub fn feed_str(self: *Self, str: []const u8) void {
    for (str) |char| {
        self.feed_char(char);
    }
}

// Testing ====================================================================

var test_print_char_buffer: [128]u8 = undefined;
var test_print_char_got: usize = 0;
fn test_print_char(self: *Self, char: u8) void {
    _ = self;
    test_print_char_buffer[test_print_char_got] = char;
    test_print_char_got += 1;
}

fn test_print_str(self: *Self, str: []const u8) void {
    for (str) |c| test_print_char(self, c);
}

fn test_reset(self: *Self) void {
    test_print_str(self, "[RESET]");
}

fn test_invert_colors(self: *Self) void {
    test_print_str(self, "[INVERT]");
}

fn test_hex_color(self: *Self, color: HexColor, layer: Layer) void {
    test_print_char(self, '[');
    test_print_char(self, if (layer == .Background) 'B' else 'F');
    test_print_str(self, "G_COLOR(");
    test_print_char(self, switch (color) {
        .LightRed => 'R',
        .Green => 'g',
        else => '?',
    });
    test_print_str(self, ")]");
}

fn test_use_default_color(self: *Self, layer: Layer) void {
    test_print_str(self, "[DEFAULT_");
    test_print_char(self, if (layer == .Background) 'B' else 'F');
    test_print_str(self, "G]");
}

test "AnsiEscProcessor" {
    var esc = Self{
        .print_char = test_print_char,
        .use_default_color = test_use_default_color,
        .reset_attributes = test_reset,
        .invert_colors = test_invert_colors,
        .hex_color = test_hex_color,
    };
    esc.feed_str("Hello \x1b[7mBob\x1b[0m \x1b[91;42mGoodbye");
    try std.testing.expectEqualStrings(
        "Hello [INVERT]Bob[RESET] [FG_COLOR(R)][BG_COLOR(g)]Goodbye",
        test_print_char_buffer[0..test_print_char_got]);
    try std.testing.expectEqual(@as(usize, 0), esc.malformed_sequences);

    test_print_char_got = 0;
    esc.feed_str("\x1b[91m<<<\x1b[39;49m\x1b[101;32m1\x1b[39;49m");
    try std.testing.expectEqualStrings(
        "[FG_COLOR(R)]<<<[DEFAULT_FG][DEFAULT_BG]" ++
            "[BG_COLOR(R)][FG_COLOR(g)]1[DEFAULT_FG][DEFAULT_BG]",
        test_print_char_buffer[0..test_print_char_got]);
    try std.testing.expectEqual(@as(usize, 0), esc.malformed_sequences);
    // TODO: More Tests
}
