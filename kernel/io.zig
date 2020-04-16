const util = @import("util.zig");

pub const FileError = error {
    /// The operation is not supported on the file.
    Unsupported,
    /// The operation would cause the position of the file stream to became
    /// invalid without getting anything else done.
    OutOfBounds,
    /// The source or destination buffer given has a size of zero.
    EmptyBuffer,
    /// The file manager could not reserve a file.
    MaxFilesReached,
};

/// File IO Interface
pub const File = struct {
    valid: bool = false,
    index: usize = 0,

    /// Pointer to Implementation Specific Data
    impl_data: ?usize = null,

    /// Used for seek()
    pub const SeekType = enum {
        FromStart,
        FromHere,
        FromEnd,
    };

    pub const nop = struct {
        fn read_impl(file: *File, to: []u8) FileError!usize {
            return 0;
        }

        fn write_impl(file: *File, from: []const u8) FileError!usize {
            return from.len;
        }

        fn seek_impl(file: *File,
                offset: isize, seek_type: SeekType) FileError!usize {
            return 0;
        }

        fn close_impl(file: *File) FileError!void {
        }
    };

    pub const unsupported = struct {
        fn read_impl(file: *File, to: []u8) FileError!usize {
            return FileError.Unsupported;
        }

        fn write_impl(file: *File, from: []const u8) FileError!usize {
            return FileError.Unsupported;
        }

        fn seek_impl(file: *File,
                offset: isize, seek_type: SeekType) FileError!usize {
            return FileError.Unsupported;
        }

        fn close_impl(file: *File) FileError!void {
            return FileError.Unsupported;
        }
    };

    read_impl: fn(*File, []u8) FileError!usize = unsupported.read_impl,
    write_impl: fn(*File, []const u8) FileError!usize = unsupported.write_impl,
    seek_impl: fn(*File, isize, SeekType) FileError!usize =
        unsupported.seek_impl,
    close_impl: fn(*File) FileError!void = unsupported.close_impl,

    /// Set the file to do nothing when used.
    pub fn set_nop_impl(self: *File) void {
        self.read_impl = nop.read_impl;
        self.write_impl = nop.write_impl;
        self.seek_impl = nop.seek_impl;
        self.close_impl = nop.close_impl;
    }

    /// Set the file to return FileError.Unsupported when used.
    pub fn set_unsupported_impl(self: *File) void {
        self.read_impl = unsupported.read_impl;
        self.write_impl = unsupported.write_impl;
        self.seek_impl = unsupported.seek_impl;
        self.close_impl = unsupported.close_impl;
    }

    /// Tries to read as much as possible into the `to` slice and will return
    /// the amount read, which may be less than `to.len`. Can return 0 if the
    /// `to` slice is zero or the end of the file has been reached already. It
    /// should never return `FileError.OutOfBounds` or `FileError.EmptyBuffer`,
    /// but `read_or_error` will. The exact return values are defined by the
    /// file implementation.
    pub inline fn read(file: *File, to: []u8) FileError!usize {
        return file.read_impl(file, to);
    }

    /// Same as `read`, but return `FileError.OutOfBounds` if an empty `to` was
    /// passed or `FileError.OutOfBounds` if trying to read from a file that's
    /// already reached the end.
    pub inline fn read_or_error(file: *File, to: []u8) FileError!usize {
        if (to.len == 0) {
            return FileError.EmptyBuffer;
        }
        const result = file.read_impl(file, to);
        if (result == 0) {
            return FileError.OutOfBounds;
        }
        return result;
    }

    /// Tries the write the entire `from` slice and will return the amount
    /// written, which may be less than `from.len`. As with `read` this can be
    /// 0 if the file has a limit of what can be written and that limit was
    /// already reached. Also like `read` this should never return
    /// `FileError.OutOfBounds` or `FileError.EmptyBuffer`, but `write_or_error`
    /// can. The exact return values are defined by the file implementation.
    pub inline fn write(file: *File, from: []const u8) FileError!usize {
        return file.write_impl(file, from);
    }

    /// Same as `write`, but return `FileError.OutOfBounds` if an empty `from`
    /// was passed or `FileError.OutOfBounds` if trying to write to a file
    /// that's already reached the end.
    pub inline fn write_or_error(file: *File, from: []const u8) FileError!usize {
        const result = file.write_impl(file, to);
        if (result == 0 and from.len > 0) {
            return FileError.OutOfBounds;
        }
        return result;
    }

    /// Shift where the file is operating from. Returns the new location if
    /// that's applicable, but if it's not it always returns 0.
    pub inline fn seek(file: *File,
            offset: isize, seek_type: File.SeekType) FileError!usize {
        return file.seek_impl(file, offset, seek_type);
    }

    /// Free resources used by the file.
    pub inline fn close(file: *File) FileError!void {
        defer file.valid = false;
        file.close_impl(file) catch |e| return e;
    }

    /// A generic seek calculation for File Implementations to call.
    /// This assumes the following:
    ///  - The start of the stream is always 0 and this is something that can
    ///    be seeked.
    ///  - The `position` can never over or under flow, or otherwise go past
    ///    start by being negative.
    ///  - There is an `end` of the stream and seek can go past there depending
    ///    on if `past_end` is `true`.
    /// The result is returned unless it's invalid, then
    /// `FileError.OutOfBounds` is returned.
    pub fn generic_seek(position: usize, end: usize, past_end: bool,
            offset: isize, seek_type: SeekType) FileError!usize {
        const from: usize = switch (seek_type) {
            .FromStart => 0,
            .FromHere => position,
            .FromEnd => end,
        };
        if (util.add_isize_to_usize(from, offset)) |result| {
            if (!past_end and result >= end) {
                return FileError.OutOfBounds;
            }
            return result;
        }
        return FileError.OutOfBounds;
    }
};

/// Test for normal situation.
fn generic_seek_subtest(seek_type: File.SeekType, expected_from: usize) FileError!void {
    const std = @import("std");
    std.testing.expectEqual(expected_from,
        try File.generic_seek(1, 4, true, 0, seek_type));
    std.testing.expectEqual(expected_from + 5,
        try File.generic_seek(1, 4, true, 5, seek_type));
    std.testing.expectError(FileError.OutOfBounds,
        File.generic_seek(1, 4, false, 5, seek_type));
    std.testing.expectError(FileError.OutOfBounds,
        File.generic_seek(1, 4, true, -5, seek_type));
    std.testing.expectError(FileError.OutOfBounds,
        File.generic_seek(1, 4, false, -5, seek_type));
}

test "File.generic_seek" {
    const std = @import("std");

    // Some normal situations
    try generic_seek_subtest(.FromStart, 0);
    try generic_seek_subtest(.FromHere, 1);
    try generic_seek_subtest(.FromEnd, 4);

    // We should be able to go to max_usize.
    const max_usize = util.max_of_int(usize);
    const max_isize = util.max_of_int(isize);
    const max_isize_as_usize = @bitCast(usize, max_isize);
    std.testing.expectEqual(max_usize,
        max_isize_as_usize + max_isize_as_usize + 1); // Just a sanity check
    std.testing.expectEqual(max_usize,
        try File.generic_seek(max_isize_as_usize + 1, 4, true, max_isize, .FromHere));
    // However we shouldn't be able to go to past max_usize.
    std.testing.expectError(FileError.OutOfBounds,
        File.generic_seek(max_usize, 4, true, 5, .FromHere));
    std.testing.expectError(FileError.OutOfBounds,
        File.generic_seek(max_usize, 4, false, 5, .FromHere));
}

/// File that reads from and writes to a provided buffer.
const BufferFile = struct {
    const Self = @This();

    file: *File = undefined,
    buffer: []u8 = undefined,
    position: usize = 0,

    pub fn initialize(self: *Self, file: *File, buffer: []u8) void {
        file.impl_data = @ptrToInt(self);
        file.read_impl = Self.read;
        file.write_impl = Self.write;
        file.seek_impl = Self.seek;
        file.close_impl = File.nop.close_impl;
        self.file = file;
        self.buffer = buffer;
        self.position = 0;
    }

    pub fn read(file: *File, to: []u8) FileError!usize {
        const self = @intToPtr(*Self, file.impl_data.?);
        const read_size = util.min(usize, to.len,
            self.buffer.len - self.position);
        if (read_size > 0) {
            const next_position = self.position + read_size;
            util.memory_copy(to[0..read_size],
                self.buffer[self.position..next_position]);
            self.position += read_size;
        }
        return read_size;
    }

    pub fn write(file: *File, from: []const u8) FileError!usize {
        const self = @intToPtr(*Self, file.impl_data.?);
        const write_size = util.min(usize, from.len,
            self.buffer.len - self.position);
        if (write_size > 0) {
            const next_position = self.position + write_size;
            util.memory_copy(self.buffer[self.position..next_position],
                from[0..write_size]);
            self.position += write_size;
        }
        return write_size;
    }

    pub fn seek(file: *File,
            offset: isize, seek_type: File.SeekType) FileError!usize {
        const self = @intToPtr(*Self, file.impl_data.?);
        const new_postion = try File.generic_seek(
            self.position, self.buffer.len, false, offset, seek_type);
        self.position = new_postion;
        return new_postion;
    }
};

test "BufferFile" {
    const std = @import("std");

    var file_buffer: [128]u8 = undefined;
    var file = File{};
    var buffer_file = BufferFile{};
    buffer_file.initialize(&file, file_buffer[0..]);

    // Put "adc123" into `file_buffer`, read it into `result_buffer`, then
    // compare them.
    const string = "abc123";
    const len = string.len;
    var result_buffer: [128]u8 = undefined;
    util.memory_copy(file_buffer[0..], string[0..]);
    buffer_file.buffer.len = string.len;
    std.testing.expectEqual(len, try file.read(result_buffer[0..]));
    // TODO: Show strings if fail?
    std.testing.expectEqualSlices(u8, string[0..], result_buffer[0..len]);

    // Seek position 3 and then read three 3 to start of result buffer
    std.testing.expectEqual(usize(3), try file.seek(3, .FromStart));
    std.testing.expectEqual(usize(3), try file.read(result_buffer[0..]));
    std.testing.expectEqualSlices(u8, "123123", result_buffer[0..len]);

    // Try to read again at the end of the file
    std.testing.expectEqual(usize(0), try file.read(result_buffer[0..]));
    std.testing.expectEqual(len, buffer_file.position);

    // Try Writing Another String Over It
    const string2 = "cdef";
    std.testing.expectEqual(usize(2), try file.seek(2, .FromStart));
    std.testing.expectEqual(usize(string2.len), try file.write(string2));
    std.testing.expectEqual(usize(0), try file.seek(0, .FromStart));
    std.testing.expectEqual(len, try file.read(result_buffer[0..]));
    std.testing.expectEqualSlices(u8, "abcdef", result_buffer[0..len]);
}

// TODO: open for BufferFile
// pub fn BufferFile_open(files: *Files, buffer: []u8) FileError!*File {
// }

/// File manager
/// TODO: Make file container size dynamic
pub fn Files(max_file_count: usize) type {
    return struct {
        const Self = @This();

        array: [max_file_count]File = undefined,

        pub fn initialize(self: *Self) FileError!void {
            for (self.array) |*file, i| {
                file.valid = false;
                file.index = i;
            }
        }

        pub fn new_file(self: *Self) FileError!*File {
            for (self.array) |*file| {
                if (!file.valid) {
                    file.valid = true;
                    file.impl_data = null;
                    file.set_unsupported_impl();
                    return file;
                }
            }
            return FileError.MaxFilesReached;
        }
    };
}
