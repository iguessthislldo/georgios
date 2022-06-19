const builtin = @import("std").builtin;

const utils = @import("utils");

const io = @import("io.zig");
const File = io.File;
const FileError = io.FileError;

/// Print a char
pub fn char(file: *File, ch: u8) FileError!void {
    _ = try file.write(([_]u8{ch})[0..]);
}

/// Print a string.
pub fn string(file: *File, str: []const u8) FileError!void {
    _ = try file.write(str);
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
    try string(file, str[0..utils.stripped_string_size(str[0..size])]);
}

fn uint_recurse(comptime uint_type: type, file: *File, value: uint_type) FileError!void {
    const digit: u8 = @intCast(u8, value % 10);
    const next = value / 10;
    if (next > 0) {
        try uint_recurse(uint_type, file, next);
    }
    try char(file, '0' + digit);
}

/// Print a unsigned integer
pub fn uint(file: *File, value: usize) FileError!void {
    if (value == 0) {
        try char(file, '0');
        return;
    }
    try uint_recurse(usize, file, value);
}

pub fn uint64(file: *File, value: u64) FileError!void {
    if (value == 0) {
        try char(file, '0');
        return;
    }
    try uint_recurse(u64, file, value);
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

fn nibble(file: *File, value: u4) FileError!void {
    try char(file, utils.nibble_char(value));
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

/// Print a unsigned integer as a hexadecimal number a padded to usize and
/// prefixed with "@0x".
pub fn address(file: *File, value: usize) FileError!void {
    const prefix = "@0x";
    // For 32b: @0xXXXXXXXX
    // For 64b: @0xXXXXXXXXXXXXXXXX
    const nibble_count = @sizeOf(usize) * 2;
    const char_count = prefix.len + nibble_count;
    var buffer: [char_count]u8 = undefined;
    for (prefix) |c, i| {
        buffer[i] = c;
    }

    for (buffer[prefix.len..]) |*ptr, i| {
        const nibble_index: usize = (nibble_count - 1) - i;
        ptr.* = utils.nibble_char(utils.select_nibble(usize, value, nibble_index));
    }

    try string(file, buffer[0..]);
}

test "address" {
    const std = @import("std");
    const BufferFile = io.BufferFile;

    var file_buffer: [128]u8 = undefined;
    utils.memory_set(file_buffer[0..], 0);
    var buffer_file = BufferFile{};
    buffer_file.init(file_buffer[0..]);
    const file = &buffer_file.file;

    try address(file, 0x7bc75e39);
    const length = utils.string_length(file_buffer[0..]);

    const expected = if (@sizeOf(usize) == 4)
        "@0x7bc75e39"
    else if (@sizeOf(usize) == 8)
        "@0x000000007bc75e39"
    else
        @compileError("usize size missing in this test");
    try std.testing.expectEqualSlices(u8, expected[0..], file_buffer[0..length]);
}

/// Print a hexadecimal representation of a byte (no "0x" prefix)
pub fn byte(file: *File, value: u8) FileError!void {
    var buffer: [2]u8 = undefined;
    utils.byte_buffer(buffer[0..], value);
    try string(file, buffer);
}

/// Print a boolean as "true" or "false".
pub fn boolean(file: *File, value: bool) FileError!void {
    try string(file, if (value) "true" else "false");
}

/// Try to guess how to print a value based on its type.
pub fn any(file: *File, value: anytype) FileError!void {
    const Type = @TypeOf(value);
    const Traits = @typeInfo(Type);
    switch (Traits) {
        builtin.TypeId.Int => |int_type| {
            if (int_type.signedness == .signed) {
                try int(file, value);
            } else {
                if (int_type.bits * 8 > @sizeOf(usize)) {
                    try uint64(file, value);
                } else {
                    try uint(file, value);
                }
            }
        },
        builtin.TypeId.Bool => try boolean(file, value),
        builtin.TypeId.Array => |array_type| {
            const t = array_type.child;
            if (t == u8) {
                try string(file, value[0..]);
            } else {
                comptime var i: usize = 0;
                inline while (i < array_type.len) {
                    try format(file, "[{}] = {},", .{i, value[i]});
                    i += 1;
                }
            }
        },
        builtin.TypeId.Pointer => |ptr_type| {
            const t = ptr_type.child;
            if (ptr_type.is_allowzero and value == 0) {
                try string(file, "null");
            } else if (t == u8) {
                if (ptr_type.size == builtin.TypeInfo.Pointer.Size.Slice) {
                    try string(file, value);
                } else {
                    try cstring(file, value);
                }
            } else {
                try any(file, value.*);
                // @compileError("Can't Print Pointer to " ++ @typeName(t));
            }
        },
        builtin.TypeId.Struct => |struct_type| {
            inline for (struct_type.fields) |field| {
                try string(file, field.name);
                try string(file, ": ");
                try any(file, @field(value, field.name));
                try string(file, "\n");
            }
        },
        builtin.TypeId.Enum => {
            if (utils.enum_name(Type, value)) |name| {
                try string(file, name);
            } else {
                try string(file, "<Invalid Value For " ++ @typeName(Type) ++ ">");
            }
        },
        else => @compileError("Can't Print " ++ @typeName(Type)),
    }
}

/// Print Using Format String, meant to work somewhat like Zig's
/// `std.fmt.format`.
///
/// Layout of a valid format marker is `{[specifier:]}`.
///
/// TODO: Match std.fmt.format instead of Python string.format and use
/// {[specifier]:...}
///
/// `specifier`:
///     None
///         Insert next argument using default formating and `fprint.any()`.
///     `x` and `X`
///         Insert next argument using hexadecimal format. It must be an
///         unsigned integer. The case of the letters A-F of the result depends
///         on if `x` or `X` was used as the specifier (TODO).
///     'a'
///         Like "x", but prints the full address value prefixed with "@".
///     'c'
///         Insert the u8 as a character (more specficially as a UTF-8 byte).
///
/// Escapes:
///     `{{` is replaced with `{` and `}}` is replaced by `}`.
pub fn format(file: *File, comptime fmtstr: []const u8, args: anytype) FileError!void {
    const State = enum {
        NoFormat, // Outside Braces
        Format, // Inside Braces
        EscapeEnd, // Expecting }
        FormatSpec, // After {:
    };

    const Spec = enum {
        Default,
        Hex,
        Address,
        Char,
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
                        Spec.Address => try address(file, args[arg]),
                        Spec.Char => try char(file, args[arg]),
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
                'a' => {
                    spec = Spec.Address;
                    state = State.Format;
                },
                'c' => {
                    spec = Spec.Char;
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

pub fn dump_memory(file: *File, ptr: usize, size: usize) FileError!void {
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
        print_buffer = !has_next;
        {
            const new_pos = buffer_pos + 2;
            utils.byte_buffer(buffer[buffer_pos..new_pos],
                @intToPtr(*allowzero u8, ptr + i).*);
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

pub fn dump_bytes(file: *File, byteslice: []const u8) FileError!void {
    try dump_memory(file, @ptrToInt(byteslice.ptr), byteslice.len);
}

pub fn dump_raw_object(file: *File, comptime Type: type, value: *const Type) FileError!void {
    const size: usize = @sizeOf(Type);
    const ptr: usize = @ptrToInt(value);
    try format(file, "type: {} at {:a} size: {} data:\n", @typeName(Type), ptr, size);
    try dump_memory(file, ptr, size);
}
