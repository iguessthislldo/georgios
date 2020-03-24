const platform = @import("platform/platform.zig");

pub const FileError = error {
    Unsupported,
    EndOfFile,
    PermissionDenied,
    InternalError,
    MaxFilesReached,
};

pub const File = struct {
    valid: bool,
    index: usize,

    /// File Type Identifier Type
    pub const FileType = enum {
        Unknown,
        Keyboard,
        Screen,
    };
    /// File Type Identifier
    file_type: FileType,

    /// Pointer to Implementation Specific Data
    impl_data: ?usize,

    pub const SeekType = enum {
        FromStart,
        FromHere,
        FromEnd,
    };

    const nop = struct {
        fn read_impl(file: *File, to: [*]u8, max_size: usize) FileError!usize {
            return error.EndOfFile;
        }

        fn write_impl(file: *File, from: [*] const u8, size: usize) FileError!usize {
            return size;
        }

        fn seek_impl(file: *File, offset: isize, seek_type: SeekType) FileError!usize {
            return 0;
        }

        fn close_impl(file: *File) FileError!void {
        }
    };

    const unsupported = struct {
        fn read_impl(file: *File, to: [*]u8, max_size: usize) FileError!usize {
            return error.Unsupported;
        }

        fn write_impl(file: *File, from: [*]const u8, size: usize) FileError!usize {
            return error.Unsupported;
        }

        fn seek_impl(file: *File, offset: isize, seek_type: SeekType) FileError!usize {
            return error.Unsupported;
        }

        fn close_impl(file: *File) FileError!void {
            return error.Unsupported;
        }
    };

    read_impl: fn(*File, [*]u8, usize) FileError!usize,
    write_impl: fn(*File, [*]const u8, usize) FileError!usize,
    seek_impl: fn(*File, isize, SeekType) FileError!usize,
    close_impl: fn(*File) FileError!void,

    pub fn init_nop() File {
        return File{
            .valid = true,
            .file_type = FileType.Unknown,
            .impl_data = null,
            .read_impl = nop.read_impl,
            .write_impl = nop.write_impl,
            .seek_impl = nop.seek_impl,
            .close_impl = nop.close_impl,
        };
    }

    pub fn init_unsupported() File {
        return File{
            .valid = true,
            .file_type = FileType.Unknown,
            .impl_data = null,
            .read_impl = nop.read_impl,
            .write_impl = nop.write_impl,
            .seek_impl = nop.seek_impl,
            .close_impl = nop.close_impl,
        };
    }

    pub inline fn read(file: *File, to: [*]u8, max_size: usize) FileError!usize {
        return file.read_impl(file, to, max_size);
    }

    pub inline fn write(file: *File, from: [*]const u8, size: usize) FileError!usize {
        return file.write_impl(file, from, size);
    }

    pub inline fn seek(file: *File, offset: isize, seek_type: SeekType) FileError!usize {
        return file.seek_impl(file, offset, seek_type);
    }

    pub inline fn close(file: *File) FileError!void {
        defer file.valid = false;
        file.close_impl(file) catch |e| return e;
    }
};

var files: [32]File = undefined;

pub var console_in: ?*File = null;
pub var console_out: ?*File = null;

pub fn new_file() FileError!*File {
    for (files) |*file| {
        if (!file.valid) {
            file.valid = true;
            return file;
        }
    }
    return error.MaxFilesReached;
}

pub fn initialize() void {
    for (files) |*file, i| {
        file.valid = false;
        file.index = i;
    }
    platform.initialize_io();
}
