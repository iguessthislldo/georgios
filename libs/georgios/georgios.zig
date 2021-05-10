const builtin = @import("builtin");

pub const utils = @import("utils");

pub const system_calls = @import("system_calls.zig");
pub const start = @import("start.zig");
pub const keyboard = @import("keyboard.zig");
pub const io = @import("io.zig");
pub const memory = @import("memory.zig");

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

pub var proc_info: if (is_program) *const ProcessInfo else void = undefined;

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
        InvalidFilesystem,
    } || io.FileError;

    pub fn open(path: []const u8) Error!io.File {
        return io.File{.valid = true, .id = try system_calls.file_open(path)};
    }
};

pub const threading = struct {
    pub const Error = error {
        NoCurrentProcess,
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
