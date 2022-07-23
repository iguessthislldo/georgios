const std = @import("std");
const builtin = @import("builtin");

pub const utils = @import("utils");

pub const system_calls = @import("system_calls.zig");
pub const start = @import("start.zig");
pub const keyboard = @import("keyboard.zig");
pub const io = @import("io.zig");
pub const memory = @import("memory.zig");
pub const ImgFile = @import("ImgFile.zig");

pub const is_cross_compiled = builtin.os.tag == .freestanding;
const root = @import("root");
pub const is_kernel = is_cross_compiled and @hasDecl(root, "kernel_main");
pub const is_program = is_cross_compiled and @hasDecl(root, "main");
comptime {
    if (is_program) {
        // Force include program stubs. Based on std.zig.
        _ = start;
    }
}

pub const ExitInfo = struct {
    status: u8 = 0,
    crashed: bool = false,

    pub fn failed(self: *const ExitInfo) bool {
        return self.status != 0 or self.crashed;
    }
};

pub var proc_info: if (is_program) *const ProcessInfo else void = undefined;

pub fn panic(msg: []const u8, trace: ?*std.builtin.StackTrace) noreturn {
    _ = trace;
    var buffer: [128]u8 = undefined;
    var ts = utils.ToString{.buffer = buffer[0..]};
    ts.string("\x1bc") catch unreachable;
    ts.string(proc_info.name) catch unreachable;
    ts.string(" panicked: ") catch unreachable;
    ts.string(msg) catch unreachable;
    ts.string("\n") catch unreachable;
    system_calls.print_string(ts.get());
    system_calls.exit(.{.status = 1});
}

pub const DirEntry = struct {
    dir: []const u8,
    dir_inode: ?usize = null,
    current_entry_buffer: [128]u8 = undefined,
    current_entry: []u8 = undefined,
    current_entry_inode: ?usize = null,
    done: bool = false,
};

pub const ProcessInfo = struct {
    path: []const u8,
    name: []const u8 = utils.make_const_slice(u8, @intToPtr([*]const u8, 1024), 0),
    args: []const []const u8 = utils.make_const_slice(
        []const u8, @intToPtr([*]const []const u8, 1024), 0),
    kernel_mode: bool = false,
};

pub const fs = struct {
    pub const Error = error {
        FileNotFound,
        NotADirectory,
        NotAFile,
        DirectoryNotEmpty,
        InvalidFilesystem,
        FilesystemAlreadyMountedHere,
    } || io.FileError;

    pub fn open(path: []const u8) Error!io.File {
        return io.File{.valid = true, .id = try system_calls.file_open(path)};
    }
};

pub const threading = struct {
    pub const Error = error {
        NoCurrentProcess,
        NoSuchProcess,
    } || utils.Error || memory.MemoryError;
};

pub const ThreadingOrFsError = fs.Error || threading.Error;

pub const elf = struct {
    pub const Error = error {
        InvalidElfFile,
        InvalidElfObjectType,
        InvalidElfPlatform,
    };
};

pub const ExecError = ThreadingOrFsError || elf.Error;

pub const Blocking = enum {
    Blocking,
    NonBlocking,
};

pub const ConsoleWriter = struct {
    pub const Error = error{};
    pub const Writer = std.io.Writer(ConsoleWriter, Error, write);

    pub fn writer(self: ConsoleWriter) Writer {
        return Writer{.context = self};
    }

    pub fn write(self: ConsoleWriter, bytes: []const u8) Error!usize {
        _ = self;
        if (is_program) {
            system_calls.print_string(bytes);
        } else {
            root.kernel.print.string(bytes);
        }
        return bytes.len;
    }
};

pub fn get_console_writer() ConsoleWriter.Writer {
    const cw = ConsoleWriter{};
    return cw.writer();
}
