const std = @import("std");

const utils = @import("utils");

const georgios = @import("georgios.zig");
const memory = @import("memory.zig");

pub const FileError = error {
    /// The operation is not supported.
    Unsupported,
    /// An Implementation-Related Error Occured.
    Internal,
    InvalidFileId,
} || utils.Error || memory.MemoryError;

/// File IO Interface
pub const File = struct {
    pub const Writer = std.io.Writer(*File, FileError, write);

    pub const Id = u32;

    /// Used for seek()
    pub const SeekType = enum {
        FromStart,
        FromHere,
        FromEnd,
    };

    pub const nop = struct {
        pub fn read_impl(file: *File, to: []u8) FileError!usize {
            _ = file;
            _ = to;
            return 0;
        }

        pub fn write_impl(file: *File, from: []const u8) FileError!usize {
            _ = file;
            return from.len;
        }

        pub fn seek_impl(file: *File,
                offset: isize, seek_type: SeekType) FileError!usize {
            _ = file;
            _ = offset;
            _ = seek_type;
            return 0;
        }

        pub fn close_impl(file: *File) FileError!void {
            _ = file;
        }
    };

    pub const unsupported = struct {
        pub fn read_impl(file: *File, to: []u8) FileError!usize {
            _ = file;
            _ = to;
            return FileError.Unsupported;
        }

        pub fn write_impl(file: *File, from: []const u8) FileError!usize {
            _ = file;
            _ = from;
            return FileError.Unsupported;
        }

        pub fn seek_impl(file: *File,
                offset: isize, seek_type: SeekType) FileError!usize {
            _ = file;
            _ = offset;
            _ = seek_type;
            return FileError.Unsupported;
        }

        pub fn close_impl(file: *File) FileError!void {
            _ = file;
            return FileError.Unsupported;
        }
    };

    pub const system_call = struct {
        pub fn read_impl(file: *File, to: []u8) FileError!usize {
            return georgios.system_calls.file_read(file.id.?, to);
        }

        pub fn write_impl(file: *File, from: []const u8) FileError!usize {
            return georgios.system_calls.file_write(file.id.?, from);
        }

        pub fn seek_impl(file: *File,
                offset: isize, seek_type: SeekType) FileError!usize {
            // TODO: Causes Zig to crash:
            // return georgios.system_calls.file_seek(file.id.?, offset, seek_type);
            _ = file;
            _ = offset;
            _ = seek_type;
            return FileError.Unsupported;
        }

        pub fn close_impl(file: *File) FileError!void {
            return georgios.system_calls.file_close(file.id.?);
        }
    };

    const default_impl = if (georgios.is_program) system_call else unsupported;

    valid: bool = false,
    id: ?Id = null,
    set_up_writer: bool = false,
    _writer: Writer = undefined,
    read_impl: fn(*File, []u8) FileError!usize = default_impl.read_impl,
    write_impl: fn(*File, []const u8) FileError!usize = default_impl.write_impl,
    seek_impl: fn(*File, isize, SeekType) FileError!usize = default_impl.seek_impl,
    close_impl: fn(*File) FileError!void = default_impl.close_impl,

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
    /// should never return `FileError.OutOfBounds` or
    /// `FileError.NotEnoughDestination`, but `read_or_error` will. The exact
    /// return values are defined by the file implementation.
    pub fn read(file: *File, to: []u8) callconv(.Inline) FileError!usize {
        return file.read_impl(file, to);
    }

    /// Same as `read`, but returns `FileError.NotEnoughDestination` if an
    /// empty `to` was passed or `FileError.OutOfBounds` if trying to read from
    /// a file that's already reached the end.
    pub fn read_or_error(file: *File, to: []u8) callconv(.Inline) FileError!usize {
        if (to.len == 0) {
            return FileError.NotEnoughDestination;
        }
        const result = try file.read_impl(file, to);
        if (result == 0) {
            return FileError.OutOfBounds;
        }
        return result;
    }

    /// Tries the write the entire `from` slice and will return the amount
    /// written, which may be less than `from.len`. As with `read` this can be
    /// 0 if the file has a limit of what can be written and that limit was
    /// already reached. Also like `read` this should never return
    /// `FileError.OutOfBounds`, but `write_or_error` can. The exact return
    /// values are defined by the file implementation.
    pub fn write(file: *File, from: []const u8) FileError!usize {
        return file.write_impl(file, from);
    }

    /// Same as `write`, but return `FileError.OutOfBounds` if an empty `from`
    /// was passed or `FileError.OutOfBounds` if trying to write to a file
    /// that's already reached the end.
    pub fn write_or_error(file: *File, from: []const u8) callconv(.Inline) FileError!usize {
        const result = file.write_impl(file, from);
        if (result == 0 and from.len > 0) {
            return FileError.OutOfBounds;
        }
        return result;
    }

    /// Shift where the file is operating from. Returns the new location if
    /// that's applicable, but if it's not it always returns 0.
    pub fn seek(file: *File, offset: isize,
            seek_type: File.SeekType) callconv(.Inline) FileError!usize {
        return file.seek_impl(file, offset, seek_type);
    }

    /// Free resources used by the file.
    pub fn close(file: *File) callconv(.Inline) FileError!void {
        defer file.valid = false;
        file.close_impl(file) catch |e| return e;
    }

    /// A generic seek calculation for File Implementations to call.
    /// This assumes the following:
    ///  - The start of the stream is always 0 and this is something that can
    ///    be seeked.
    ///  - The `position` can never over or under flow, or otherwise go past
    ///    start by being negative.
    ///  - If `limit` is non-null, then the stream position can't go past it.
    /// The result is returned unless it's invalid, then
    /// `FileError.OutOfBounds` is returned.
    pub fn generic_seek(position: usize, end: usize, limit: ?usize,
            offset: isize, seek_type: SeekType) FileError!usize {
        const from: usize = switch (seek_type) {
            .FromStart => 0,
            .FromHere => position,
            .FromEnd => end,
        };
        if (utils.add_isize_to_usize(from, offset)) |result| {
            if (result != position and limit != null and result >= limit.?) {
                return FileError.OutOfBounds;
            }
            return result;
        }
        return FileError.OutOfBounds;
    }

    pub fn get_writer(self: *File) *Writer {
        if (!self.set_up_writer) {
            self._writer = Writer{.context = self};
            self.set_up_writer = true;
        }
        return &self._writer;
    }

    // fn writer_write(self: *File, bytes: []const u8) FileError!void {
    //     _ = try self.write(bytes);
    // }
};

/// Test for normal situation.
fn generic_seek_subtest(seek_type: File.SeekType, expected_from: usize) !void {
    try std.testing.expectEqual(expected_from,
        try File.generic_seek(1, 4, null, 0, seek_type));
    try std.testing.expectEqual(expected_from + 5,
        try File.generic_seek(1, 4, null, 5, seek_type));
    try std.testing.expectError(FileError.OutOfBounds,
        File.generic_seek(1, 4, 4, 5, seek_type));
    try std.testing.expectError(FileError.OutOfBounds,
        File.generic_seek(1, 4, 4, -5, seek_type));
    try std.testing.expectError(FileError.OutOfBounds,
        File.generic_seek(1, 4, 4, -5, seek_type));
}

test "File.generic_seek" {
    // Some normal situations
    try generic_seek_subtest(.FromStart, 0);
    try generic_seek_subtest(.FromHere, 1);
    try generic_seek_subtest(.FromEnd, 4);

    // We should be able to go to max_usize.
    const max_usize = utils.max_of_int(usize);
    const max_isize = utils.max_of_int(isize);
    const max_isize_as_usize = @bitCast(usize, max_isize);
    try std.testing.expectEqual(max_usize,
        max_isize_as_usize + max_isize_as_usize + 1); // Just a sanity check
    try std.testing.expectEqual(max_usize,
        try File.generic_seek(max_isize_as_usize + 1, 4, null, max_isize, .FromHere));
    // However we shouldn't be able to go to past max_usize.
    try std.testing.expectError(FileError.OutOfBounds,
        File.generic_seek(max_usize, 4, null, 5, .FromHere));
    try std.testing.expectError(FileError.OutOfBounds,
        File.generic_seek(max_usize, 4, 4, 5, .FromHere));
}

/// File that reads from and writes to a provided fixed buffer.
pub const BufferFile = struct {
    const Self = @This();

    file: File = undefined,
    buffer: []u8 = undefined,
    position: usize = 0,
    written_up_until: usize = 0,

    pub fn init(self: *Self, buffer: []u8) void {
        self.file.read_impl = Self.read;
        self.file.write_impl = Self.write;
        self.file.seek_impl = Self.seek;
        self.file.close_impl = File.nop.close_impl;
        self.buffer = buffer;
        self.reset();
    }

    pub fn reset(self: *Self) void {
        self.position = 0;
        self.written_up_until = 0;
    }

    pub fn read(file: *File, to: []u8) FileError!usize {
        const self = @fieldParentPtr(Self, "file", file);
        if (self.written_up_until > self.position) {
            const read_size = self.written_up_until - self.position;
            _ = utils.memory_copy_truncate(to[0..read_size],
                self.buffer[self.position..self.written_up_until]);
            self.position = self.written_up_until;
            return read_size;
        }
        return 0;
    }

    fn fill_unwritten(self: *Self, pos: usize) void {
        if (pos > self.written_up_until) {
            utils.memory_set(self.buffer[self.written_up_until..pos], 0);
        }
    }

    pub fn write(file: *File, from: []const u8) FileError!usize {
        const self = @fieldParentPtr(Self, "file", file);
        const write_size = utils.min(usize, from.len, self.buffer.len - self.position);
        if (write_size > 0) {
            self.fill_unwritten(self.position);
            const new_position = self.position + write_size;
            _ = utils.memory_copy_truncate(self.buffer[self.position..new_position],
                from[0..write_size]);
            self.position = new_position;
            self.written_up_until = new_position;
        }
        return write_size;
    }

    pub fn seek(file: *File,
            offset: isize, seek_type: File.SeekType) FileError!usize {
        const self = @fieldParentPtr(Self, "file", file);
        const new_postion = try File.generic_seek(
            self.position, self.written_up_until, self.buffer.len, offset, seek_type);
        self.position = new_postion;
        return new_postion;
    }

    pub fn set_contents(
            self: *Self, offset: usize, new_contents: []const u8) utils.Error!void {
        self.fill_unwritten(offset);
        self.written_up_until = offset +
            try utils.memory_copy_error(self.buffer[offset..], new_contents);
    }

    pub fn get_contents(self: *Self) []u8 {
        return self.buffer[0..self.written_up_until];
    }

    pub fn expect(self: *Self, expected_contents: []const u8) !void {
        try std.testing.expectEqualSlices(u8, expected_contents, self.get_contents());
    }
};

test "BufferFile" {
    var file_buffer: [128]u8 = undefined;
    var buffer_file = BufferFile{};
    buffer_file.init(file_buffer[0..]);
    const file = &buffer_file.file;

    // Put "adc123" into `file_buffer`, read it into `result_buffer`, then
    // compare them.
    const string = "abc123";
    const len = string.len;
    var result_buffer: [128]u8 = undefined;
    try buffer_file.set_contents(0, string);
    try std.testing.expectEqual(len, try file.read(result_buffer[0..]));
    // TODO: Show strings if fail?
    try std.testing.expectEqualSlices(u8, string[0..], result_buffer[0..len]);
    try buffer_file.expect(string[0..]);

    // Seek position 3 and then read three 3 to start of result buffer
    try std.testing.expectEqual(@as(usize, 3), try file.seek(3, .FromStart));
    try std.testing.expectEqual(@as(usize, 3), try file.read(result_buffer[0..]));
    try std.testing.expectEqualSlices(u8, "123123", result_buffer[0..len]);

    // Try to read again at the end of the file
    try std.testing.expectEqual(@as(usize, 0), try file.read(result_buffer[0..]));
    try std.testing.expectEqual(len, buffer_file.position);

    // Try Writing Another String Over It
    const string2 = "cdef";
    try std.testing.expectEqual(@as(usize, 2), try file.seek(2, .FromStart));
    try std.testing.expectEqual(@as(usize, string2.len), try file.write(string2));
    try std.testing.expectEqual(@as(usize, 0), try file.seek(0, .FromStart));
    try std.testing.expectEqual(len, try file.read(result_buffer[0..]));
    try std.testing.expectEqualSlices(u8, "abcdef", result_buffer[0..len]);

    // Unwritten With Set Contents
    {
        buffer_file.reset();
        const blank = "\x00\x00\x00\x00\x00\x00\x00\x00";
        const str = "Georgios";
        try buffer_file.set_contents(blank.len, str);
        try buffer_file.expect(blank ++ str);
    }

    // Unwritten With Seek
    {
        buffer_file.reset();
        const str1 = "123";
        try std.testing.expectEqual(str1.len, try file.write(str1));
        try std.testing.expectEqual(str1.len, buffer_file.written_up_until);
        const blank = "\x00\x00\x00\x00\x00\x00\x00\x00";
        const expected1 = str1 ++ blank;
        try std.testing.expectEqual(expected1.len,
            try file.seek(expected1.len, .FromStart));
        try std.testing.expectEqual(str1.len, buffer_file.written_up_until);
        try buffer_file.expect(str1);
        const str2 = "4567";
        try std.testing.expectEqual(str2.len, try file.write(str2));
        const expected2 = expected1 ++ str2;
        try buffer_file.expect(expected2);
    }

    // Try to Write and Read End Of Buffer
    {
        buffer_file.reset();
        const str = "xyz";
        const pos = file_buffer.len - str.len;
        try buffer_file.set_contents(pos, str);
        try std.testing.expectEqual(pos, try file.seek(-@as(isize, str.len), .FromEnd));
        try std.testing.expectEqual(str.len, try file.read(result_buffer[0..]));
        try std.testing.expectEqualSlices(u8, str[0..], result_buffer[0..str.len]);
        try std.testing.expectEqual(@as(usize, 0), try file.write("ijk"));
        try std.testing.expectEqual(@as(usize, 0), try file.read(result_buffer[0..]));
    }
}
