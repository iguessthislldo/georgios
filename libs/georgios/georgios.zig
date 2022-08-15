const std = @import("std");
const builtin = @import("builtin");

pub const utils = @import("utils");

pub const system_calls = @import("system_calls.zig");
pub const start = @import("start.zig");
pub const keyboard = @import("keyboard.zig");
pub const io = @import("io.zig");
pub const memory = @import("memory.zig");
pub const ImgFile = @import("ImgFile.zig");

pub var page_allocator: std.mem.Allocator = undefined;

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
    ts.string(proc_info.name) catch unreachable;
    ts.string(" panicked: ") catch unreachable;
    ts.string(msg) catch unreachable;
    ts.string("\n") catch unreachable;
    system_calls.print_string(ts.get());
    system_calls.exit(.{.status = 1});
}

pub const ProcessInfo = struct {
    path: []const u8,
    name: []const u8 = utils.empty_slice(u8, 1024),
    args: []const []const u8 = utils.empty_slice([]const u8, 1024),
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
        InvalidOpenOpts,
    } || io.FileError;

    pub const OpenOptsKind = enum {
        ReadOnly,
        Write,
    };

    pub const Exist = enum {
        CreateIfNeeded,
        MustExist,
        MustCreate,
    };

    pub const OpenOpts = union (OpenOptsKind) {
        ReadOnly: struct {
            dir: bool = false,
        },
        Write: struct {
            read: bool = false,
            exist: Exist = .CreateIfNeeded,
            append: bool = false, // Conflicts with MustCreate and truncate
            truncate: bool = false, // Conflicts with append
        },

        pub fn check(self: *const OpenOpts) Error!void {
            switch (self.*) {
                .ReadOnly => {},
                .Write => |w| {
                    if (w.append and w.truncate or
                            w.exist == .MustCreate and w.append) {
                        return Error.InvalidOpenOpts;
                    }
                },
            }
        }

        pub fn must_exist(self: *const OpenOpts) bool {
            return switch (self.*) {
                .ReadOnly => true,
                .Write => |w| w.exist == .MustExist,
            };
        }

        pub fn dir(self: *const OpenOpts) bool {
            return switch (self.*) {
                .ReadOnly => |*ropts| ropts.dir,
                else => false,
            };
        }

        pub fn from_fopen_mode(mode: []const u8) Error!OpenOpts {
            if (mode.len == 0) return Error.InvalidOpenOpts;
            if (utils.starts_with(mode, "r+")) {
                return OpenOpts{.Write = .{.read = true}};
            }
            if (utils.starts_with(mode, "r")) {
                return OpenOpts.ReadOnly;
            }
            if (utils.starts_with(mode, "w+x")) {
                return OpenOpts{.Write = .{.truncate = true, .read = true, .exist = .MustCreate}};
            }
            if (utils.starts_with(mode, "wx")) {
                return OpenOpts{.Write = .{.truncate = true, .exist = .MustCreate}};
            }
            if (utils.starts_with(mode, "w+")) {
                return OpenOpts{.Write = .{.truncate = true, .read = true}};
            }
            if (utils.starts_with(mode, "w")) {
                return OpenOpts{.Write = .{.truncate = true}};
            }
            if (utils.starts_with(mode, "a+")) {
                return OpenOpts{.Write = .{.append = true, .read = true}};
            }
            if (utils.starts_with(mode, "a")) {
                return OpenOpts{.Write = .{.append = true}};
            }
            return Error.InvalidOpenOpts;
        }
    };

    pub fn open(path: []const u8, opts: OpenOpts) Error!io.File {
        try opts.check();
        return io.File{.id = try system_calls.file_open(path, opts)};
    }

    pub fn fopen(path: []const u8, mode: []const u8) Error!io.File {
        return open(path, try OpenOpts.from_fopen_mode(mode));
    }
};

pub const BasicError = utils.Error || memory.MemoryError;

pub const threading = struct {
    pub const Error = error {
        NoCurrentProcess,
        NoSuchProcess,
    } || BasicError;
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
        } else if (is_kernel) {
            root.kernel.print.string(bytes);
        } else {
            @compileError("ConsoleWriter doesn't support this yet");
        }
        return bytes.len;
    }
};

pub fn get_console_writer() ConsoleWriter.Writer {
    const cw = ConsoleWriter{};
    return cw.writer();
}
