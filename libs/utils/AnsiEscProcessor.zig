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

// TODO
pub const HexColor = enum {
    White,
    LightGray,
    DarkGray,
    Black,
    Red,
    Green,
    Yellow,
    Blue,
    Magenta,
    Cyan,
    LightRed,
    LightGreen,
    LightYellow,
    LightBlue,
    LightMagenta,
    LightCyan,
};

const State = enum {
    Unescaped,
    Escaped,
    Csi,
};

print_char: ?fn(u8) void = null,
invert_colors: ?fn() void = null,
backspace: ?fn() void = null,
newline: ?fn() void = null,
reset_attributes: ?fn () void = null,
reset_terminal: ?fn () void = null,
move_cursor: ?fn (r: usize, c: usize) void = null,
show_cursor: ?fn (show: bool) void = null,

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
        const parameter_str = self.saved[self.parameter_start.?..self.saved_so_far];
        if (std.fmt.parseUnsigned(u16, parameter_str, 10)) |p| {
            parameter = p;
        } else |e| {
            return true;
        }
        self.parameter_start = null;
    } else { // empty parameter
        parameter = 0;
    }
    if (parameter) |p| {
        // std.debug.warn("Parameter: {}\n", .{p});
        if (self.parameter_count < self.parameters.len) {
            self.parameters[self.parameter_count] = p;
            self.parameter_count += 1;
        } else {
            return true;
        }
    }
    return false;
}

fn select_graphic_rendition(self: *Self) void {
    var i: usize = 0;
    while (i < self.parameter_count) {
        const p = self.parameters[i];
        // std.debug.warn("SGR: {}\n", .{p});
        switch (p) {
            0 => if (self.reset_attributes) |reset_attributes| reset_attributes(),
            7 => if (self.invert_colors) |invert_colors| invert_colors(),
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
        move_cursor(row, column);
    }
}

pub fn feed_char(self: *Self, char: u8) void {
    self.saved[self.saved_so_far] = char;

    // std.debug.warn("feed_char {c}\n", .{char});
    var abort = false;
    var reset = false;
    switch (self.state) {
        .Unescaped => {
            reset = true;
            switch (char) {
                0x08 => if (self.backspace) |backspace| backspace(),

                '\n' => {
                    if (self.newline) |newline| {
                        newline();
                    } else if (self.print_char) |print_char| {
                        print_char(char);
                    }
                },

                0x1b => {
                    self.state = .Escaped;
                    reset = false;
                },

                else => {
                    if (self.print_char) |print_char| {
                        print_char(char);
                    }
                },
            }
        },

        .Escaped => {
            switch (char) {
                '[' => self.state = .Csi,

                'c' => {
                    if (self.reset_terminal) |reset_terminal| {
                        reset_terminal();
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
                            show_cursor(false);
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
        // std.debug.warn("Abort\n", .{});
        if (self.print_char) |print_char| {
            // Dump the malformed sequence. Seems to be what Gnome's terminal does.
            for (self.saved[0..self.saved_so_far]) |c| {
                print_char(c);
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

    // std.debug.warn("state {s}\n", .{@tagName(self.state)});
}

pub fn feed_str(self: *Self, str: []const u8) void {
    for (str) |char| {
        self.feed_char(char);
    }
}

// Testing ====================================================================

var test_print_char_buffer: [128]u8 = undefined;
var test_print_char_got: usize = 0;
fn test_print_char(char: u8) void {
    test_print_char_buffer[test_print_char_got] = char;
    test_print_char_got += 1;
}

fn test_reset() void {
    test_print_char('R');
}

fn test_invert_colors() void {
    test_print_char('I');
}

test "AnsiEscProcessor" {
    var esc = Self{
        .print_char = test_print_char,
        .reset_attributes = test_reset,
        .invert_colors = test_invert_colors,
    };
    esc.feed_str("Hello \x1b[7mBob\x1b[0m Goodbye");
    try std.testing.expectEqualSlices(u8, "Hello IBobR Goodbye",
        test_print_char_buffer[0..test_print_char_got]);

    // TODO: More Tests
}
