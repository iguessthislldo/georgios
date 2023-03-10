const std = @import("std");
const builtin = @import("builtin");

pub const utils = @import("utils");

pub const system_calls = @import("system_calls.zig");
pub const send = system_calls.send;
pub const recv = system_calls.recv;
pub const call = system_calls.call;
pub const start = @import("start.zig");
pub const keyboard = @import("keyboard.zig");
pub const io = @import("io.zig");
pub const memory = @import("memory.zig");
pub const ImgFile = @import("ImgFile.zig");
pub const Directory = @import("fs.zig").Directory;
pub const Console = @import("Console.zig");

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
        AlreadyExists,
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

    pub const NodeKind = struct {
        file: bool = false,
        directory: bool = false,
    };
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
            @compileError("ConsoleWriter doesn't know what to do here. " ++
                "is_program and is_kernel are both false");
        }
        return bytes.len;
    }
};

pub fn get_console_writer() ConsoleWriter.Writer {
    const cw = ConsoleWriter{};
    return cw.writer();
}

pub const MouseEvent = struct {
    rmb_pressed: bool,
    mmb_pressed: bool,
    lmb_pressed: bool,
    delta: utils.Point(i32),
};

pub const DispatchError = error {
    DispatchInvalidPort,
    DispatchInvalidMessage,
    DispatchBrokenCall,
    DispatchOpUnsupported,
} || BasicError;

pub const PortId = u32;
pub const MetaPort: PortId = 1;
pub const FirstDynamicPort = MetaPort;

pub const Dispatch = struct {
    msg: []const u8,
    dst: PortId = 0,
    src: PortId = 0,
};

pub const Blocks = union (enum) {
    NonBlocking,
    Blocking: ?u32,
};

pub const SendOpts = struct {
    blocks: Blocks = .{.Blocking = null},
};

pub const RecvOpts = struct {
    blocks: Blocks = .{.Blocking = null},
};

pub const CallOpts = struct {
    blocks: Blocks = .{.Blocking = null},
};

pub fn msg_cast(comptime T: type, dispatch: Dispatch) DispatchError!*const T {
    if (dispatch.msg.len == @sizeOf(T)) {
        return @alignCast(@alignOf(T), &std.mem.bytesAsSlice(T, dispatch.msg)[0]);
    }
    return DispatchError.DispatchInvalidMessage;
}

pub fn send_value(value: anytype, dst: PortId, opts: SendOpts) DispatchError!void {
    try send(.{.msg = std.mem.asBytes(value), .dst = dst}, opts);
}
