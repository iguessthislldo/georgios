pub const utils = @import("utils");

pub const system_calls = @import("system_calls.zig");
pub const start = @import("start.zig");
pub const keyboard = @import("keyboard.zig");

const root = @import("root");
const is_program = @hasDecl(root, "main");
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
    args: []const []const u8 = utils.make_const_slice([]const u8, @intToPtr([*]const []const u8, 1024), 0),
    kernel_mode: bool = false,
};
