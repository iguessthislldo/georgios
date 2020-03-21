const isspace = @import("util.zig").isspace;
const builtin = @import("builtin");

/// Print a char
pub fn char(ch: u8) void {
    if (@import("io.zig").console_out) |o| {
        _ = o.write(@ptrCast([*]const u8, &ch), 1) catch unreachable;
    }
}

/// Print an exact amount of characters in a string.
pub fn nstring(str: [*]const u8, size: usize) void {
    if (@import("io.zig").console_out) |o| {
        _ = o.write(str, size) catch unreachable;
    }
}

/// Print a string.
pub fn string(str: []const u8) void {
    nstring(str.ptr, str.len);
}

/// Print a string with a null terminator.
pub fn cstring(str: [*]const u8) void {
    var i: usize = 0;
    while (str[i] > 0) {
        char(str[i]);
        i += 1;
    }
}

/// Print string stripped of trailing whitespace.
pub fn stripped_string(str: [*]const u8, size: usize) void {
    var i: usize = 0;
    var keep: usize = 0;
    while (i < size and str[i] > 0) {
        if (!isspace(str[i])) keep = i + 1;
        i += 1;
    }
    nstring(str, keep);
}

fn uint_recurse(value: usize) void {
    const digit: u8 = @intCast(u8, value % 10);
    const next = value / 10;
    if (next > 0) {
        uint_recurse(next);
    }
    char('0' + digit);
}

/// Print a unsigned integer
pub fn uint(value: usize) void {
    if (value == 0) {
        char('0');
        return;
    }
    uint_recurse(value);
}

/// Print a signed integer
pub fn int(value: isize) void {
    var x = value;
    if (value < 0) {
        char('-');
        x = -value;
    }
    uint(@intCast(usize, x));
}

/// Print a signed integer with an optional '+' sign.
pub fn int_sign(value: usize, show_positive: bool) void {
    if (value > 0 and show_positive) {
        char('+');
    }
    int(value);
}

fn nibble(value: u4) void {
    if (value < 10) {
        char('0' + @intCast(u8, value));
    } else {
        char('A' + @intCast(u8, value - 10));
    }
}

fn hex_recurse(value: usize) void {
    const next = value / 0x10;
    if (next > 0) {
        hex_recurse(next);
    }
    nibble(@intCast(u4, value % 0x10));
}

/// Print a unsigned integer as a hexadecimal number with a "0x" prefix
pub fn hex(value: usize) void {
    string("0x");
    if (value == 0) {
        char('0');
        return;
    }
    hex_recurse(value);
}

/// Print a hexadecimal representation of a byte (no "0x" prefix)
pub fn byte(value: u8) void {
    nibble(@intCast(u4, value >> 4));
    nibble(@intCast(u4, value % 0x10));
}

pub fn boolean(value: bool) void {
    if (value) {
        string("true");
    } else {
        string("false");
    }
}

pub fn any(value: var) void {
    const Type = @typeOf(value);
    const Traits = @typeInfo(Type);
    var invalid: bool = false;
    switch (Traits) {
        builtin.TypeId.Int => |int_type| {
            if (int_type.is_signed) {
                int(value);
            } else {
                uint(value);
            }
        },
        builtin.TypeId.Bool => boolean(value),
        builtin.TypeId.Array => |array_type| {
            const t = array_type.child;
            if (t == u8) {
                string(value);
            } else {
                @compileError("Can't Print Array of " ++ @typeName(t));
            }
        },
        builtin.TypeId.Pointer => |ptr_type| {
            const t = ptr_type.child;
            if (t == u8) {
                if (ptr_type.size == builtin.TypeInfo.Pointer.Size.Slice) {
                    string(value);
                } else {
                    cstring(value);
                }
            } else {
                @compileError("Can't Print Pointer to " ++ @typeName(t));
            }
        },
        else => @compileError("Can't Print " ++ @typeName(Type)),
    }
}

/// Print Using Format String
///
/// {} - Insert next argument using default formating.
/// {:x} - Insert next argument using hexadecimal format. It must be an
///     unsigned integer.
/// {{ - Insert '{'.
/// }} - Insert '}'.
pub fn format(comptime fmtstr: []const u8, args: ...) void {
    const State = enum {
        NoFormat, // Ouside Braces
        Format, // Inside Braces
        EscapeEnd, // Epecting }
        FormatSpec, // After {:
    };

    const Spec = enum {
        Default,
        Hex,
    };

    comptime var arg: usize = 0;
    comptime var state = State.NoFormat;
    comptime var spec = Spec.Default;
    comptime var no_format_start: usize = 0;

    inline for (fmtstr) |ch, index| {
        switch (state) {
            State.NoFormat => switch (ch) {
                '{' => {
                    if (no_format_start < index) {
                        string(fmtstr[no_format_start..index]);
                    }
                    state = State.Format;
                    spec = Spec.Default;
                },
                '}' => { // Should be Escaped }
                    if (no_format_start < index) {
                        string(fmtstr[no_format_start..index]);
                    }
                    state = State.EscapeEnd;
                },
                else => {},
            },
            State.Format => switch (ch) {
                '{' => { // Escaped {
                    state = State.NoFormat;
                    no_format_start = index;
                },
                '}' => {
                    switch (spec) {
                        Spec.Hex => hex(args[arg]),
                        Spec.Default => any(args[arg]),
                    }
                    arg += 1;
                    state = State.NoFormat;
                    no_format_start = index + 1;
                },
                ':' => {
                    state = State.FormatSpec;
                },
                else => @compileError(
                    "Unexpected Format chacter: " ++ fmtstr[index..index+1]),
            },
            State.FormatSpec => switch (ch) {
                'x' => {
                    spec = Spec.Hex;
                    state = State.Format;
                },
                else => @compileError(
                    "Unexpected Format chacter after ':': " ++
                        fmtstr[index..index+1]),
            },
            State.EscapeEnd => switch (ch) {
                '}' => { // Escaped }
                    state = State.NoFormat;
                    no_format_start = index;
                },
                else => @compileError(
                    "Expected } for end brace escape, but found: " ++
                        fmtstr[index..index+1]),
            },
        }
    }
    if (args.len != arg) {
        @compileError("Unused arguments");
    }
    if (state != State.NoFormat) {
        @compileError("Incomplete format string: " ++ fmtstr);
    }
    if (no_format_start < fmtstr.len) {
        string(fmtstr[no_format_start..fmtstr.len]);
    }
}

// void print_data(u1 * ptr, u4 size);

// size_t sprint_uint(u4 value, char * output);

// size_t sprint_size(mem_t size, char * buffer, size_t buffer_size);

// print.string("0x0 -> ");
// print.hex(0x0);
// print.char('\n');
// print.string("0x1 -> ");
// print.hex(0x1);
// print.char('\n');
// print.string("0x9 -> ");
// print.hex(0x9);
// print.char('\n');
// print.string("0xA -> ");
// print.hex(0xA);
// print.char('\n');
// print.string("0xF -> ");
// print.hex(0xF);
// print.char('\n');
// print.string("0x10 -> ");
// print.hex(0x10);
// print.char('\n');
// print.string("0xABCDEF -> ");
// print.hex(0xABCDEF);
// print.char('\n');

// print.byte(0x00);
// print.char('\n');
// print.byte(0x01);
// print.char('\n');
// print.byte(0x0F);
// print.char('\n');
// print.byte(0xFF);
// print.char('\n');

// var b: bool = false;
// var x: u16 = 0xABCD;
// print.format("Hello {} {}\n", @intCast(usize, 10), b);
// print.format("Strings {} {}\n", "Hello1", c"Hello2");
// print.format("{{These braces are escaped}}\n");
// print.format("{:x}\n", x);
