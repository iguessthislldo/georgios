const builtin = @import("builtin");

const isspace = @import("util.zig").isspace;
const io = @import("io.zig");
const File = io.File;
const FileError = io.FileError;

/// Print a char
pub fn char(file: *File, ch: u8) FileError!void {
    _ = try file.write(@ptrCast([*]const u8, &ch), 1);
}

/// Print an exact amount of characters in a string.
pub fn nstring(file: *File, str: [*]const u8, size: usize) FileError!void {
    _ = try file.write(str, size);
}

/// Print a string.
pub fn string(file: *File, str: []const u8) FileError!void {
    try nstring(file, str.ptr, str.len);
}

/// Print a string with a null terminator.
pub fn cstring(file: *File, str: [*]const u8) FileError!void {
    var i: usize = 0;
    while (str[i] > 0) {
        try char(file, str[i]);
        i += 1;
    }
}

/// Print string stripped of trailing whitespace.
pub fn stripped_string(file: *File, str: [*]const u8, size: usize) FileError!void {
    var i: usize = 0;
    var keep: usize = 0;
    while (i < size and str[i] > 0) {
        if (!isspace(str[i])) keep = i + 1;
        i += 1;
    }
    try nstring(file, str, keep);
}

fn uint_recurse(file: *File, value: usize) FileError!void {
    const digit: u8 = @intCast(u8, value % 10);
    const next = value / 10;
    if (next > 0) {
        try uint_recurse(file, next);
    }
    try char(file, '0' + digit);
}

/// Print a unsigned integer
pub fn uint(file: *File, value: usize) FileError!void {
    if (value == 0) {
        try char(file, '0');
        return;
    }
    try uint_recurse(file, value);
}

/// Print a signed integer
pub fn int(file: *File, value: isize) FileError!void {
    var x = value;
    if (value < 0) {
        try char(file, '-');
        x = -value;
    }
    try uint(file, @intCast(usize, x));
}

/// Print a signed integer with an optional '+' sign.
pub fn int_sign(file: *File, value: usize, show_positive: bool) FileError!void {
    if (value > 0 and show_positive) {
        try char(file, '+');
    }
    try int(file, value);
}

fn nibble_char(value: u4) u8 {
    return
        if (value < 10)
            '0' + @intCast(u8, value)
        else
            'A' + @intCast(u8, value - 10);
}

fn nibble(file: *File, value: u4) FileError!void {
    try char(file, nibble_char(value));
}

fn hex_recurse(file: *File, value: usize) FileError!void {
    const next = value / 0x10;
    if (next > 0) {
        try hex_recurse(file, next);
    }
    try nibble(file, @intCast(u4, value % 0x10));
}

/// Print a unsigned integer as a hexadecimal number with a "0x" prefix
pub fn hex(file: *File, value: usize) FileError!void {
    try string(file, "0x");
    if (value == 0) {
        try char(file, '0');
        return;
    }
    try hex_recurse(file, value);
}

/// Insert a hex byte to into a buffer. Common to byte() and data().
fn byte_buffer(buffer: []u8, value: u8) void {
    buffer[0] = nibble_char(@intCast(u4, value >> 4));
    buffer[1] = nibble_char(@intCast(u4, value % 0x10));
}

/// Print a hexadecimal representation of a byte (no "0x" prefix)
pub fn byte(file: *File, value: u8) FileError!void {
    var buffer: [2]u8 = undefined;
    byte_buffer(buffer[0..buffer.len], value);
    try string(file, buffer);
}

pub fn boolean(file: *File, value: bool) FileError!void {
    try string(file, if (value) "true" else "false");
}

pub fn any(file: *File, value: var) FileError!void {
    const Type = @typeOf(value);
    const Traits = @typeInfo(Type);
    var invalid: bool = false;
    switch (Traits) {
        builtin.TypeId.Int => |int_type| {
            if (int_type.is_signed) {
                try int(file, value);
            } else {
                try uint(file, value);
            }
        },
        builtin.TypeId.Bool => try boolean(file, value),
        builtin.TypeId.Array => |array_type| {
            const t = array_type.child;
            if (t == u8) {
                try string(file, value);
            } else {
                @compileError("Can't Print Array of " ++ @typeName(t));
            }
        },
        builtin.TypeId.Pointer => |ptr_type| {
            const t = ptr_type.child;
            if (t == u8) {
                if (ptr_type.size == builtin.TypeInfo.Pointer.Size.Slice) {
                    try string(file, value);
                } else {
                    try cstring(file, value);
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
pub fn format(file: *File, comptime fmtstr: []const u8, args: ...) FileError!void {
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
                        try string(file, fmtstr[no_format_start..index]);
                    }
                    state = State.Format;
                    spec = Spec.Default;
                },
                '}' => { // Should be Escaped }
                    if (no_format_start < index) {
                        try string(file, fmtstr[no_format_start..index]);
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
                        Spec.Hex => try hex(file, args[arg]),
                        Spec.Default => try any(file, args[arg]),
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
        try string(file, fmtstr[no_format_start..fmtstr.len]);
    }
}

pub fn data(file: *File, ptr: usize, size: usize) FileError!void {
    // Print hex data like this:
    //                        VV group_sep
    // 00 01 02 03 04 05 06 07  08 09 0A 0B 0C 0D 0E 0F
    // ^^ Byte ^ byte_sep  Group^^^^^^^^^^^^^^^^^^^^^^^
    const group_byte_count = 8;
    const byte_sep = " ";
    const group_size =
        group_byte_count * 2 + // Bytes
        ((group_byte_count * byte_sep.len) - 1); // byte_sep Between Bytes
    const group_count = 2;
    const buffer_byte_count = group_byte_count * group_count;
    const group_sep = "  ";
    const buffer_size =
        group_size * group_count + // Groups
        (group_count - 1) * group_sep.len + // group_sep Between Groups
        1; // Newline

    var buffer: [buffer_size]u8 = undefined;
    var i: usize = 0;
    var buffer_pos: usize = 0;
    var byte_i: usize = 0;
    var group_i: usize = 0;
    var has_next = i < size;
    var print_buffer = false;
    while (has_next) {
        const next_i = i + 1;
        has_next = next_i < size;
        {
            const new_pos = buffer_pos + 2;
            byte_buffer(buffer[buffer_pos..new_pos], @intToPtr(*u8, ptr + i).*);
            buffer_pos = new_pos;
        }
        byte_i += 1;
        if (byte_i == group_byte_count) {
            byte_i = 0;
            group_i += 1;
            if (group_i == group_count) {
                group_i = 0;
                print_buffer = true;
            } else {
                for (group_sep[0..group_sep.len]) |b| {
                    buffer[buffer_pos] = b;
                    buffer_pos += 1;
                }
            }
        } else if (has_next) {
            for (byte_sep[0..byte_sep.len]) |b| {
                buffer[buffer_pos] = b;
                buffer_pos += 1;
            }
        } else { // Done In Middle Of Row
            print_buffer = true;
        }
        if (print_buffer) {
            buffer[buffer_pos] = '\n';
            buffer_pos += 1;
            try string(file, buffer[0..buffer_pos]);
            buffer_pos = 0;
            print_buffer = false;
        }
        i = next_i;
    }
}
