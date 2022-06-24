const std = @import("std");
const builtin = @import("builtin");
const build_options = @import("build_options");

const utils = @import("utils");
const georgios = @import("georgios");

pub const platform = @import("platform.zig");
pub const fprint = @import("fprint.zig");
pub const print = @import("print.zig");
pub const memory = @import("memory.zig");
pub const io = @import("io.zig");
pub const elf = @import("elf.zig");
pub const devices = @import("devices.zig");
pub const threading = @import("threading.zig");
pub const fs = @import("fs.zig");
pub const sync = @import("sync.zig");
pub const keys = @import("keys.zig");
pub const font = @import("font.zig");
pub const Console = @import("Console.zig");

pub var panic_message: []const u8 = "";

pub fn panic(msg: []const u8, trace: ?*std.builtin.StackTrace) noreturn {
    print.format("panic: {}\n", .{msg});
    platform.impl.ps2.anykey();
    panic_message = msg;
    if (trace) |t| {
        print.format("index: {}\n", .{t.index});
        for (t.instruction_addresses) |addr| {
            if (addr == 0) break;
            print.format(" - {:a}\n", .{addr});
        }
    } else {
        print.string("No Stack Trace\n");
    }
    platform.panic(msg, trace);
}

pub var memory_mgr = memory.Manager{};
pub var device_mgr = devices.Manager{};
pub var threading_mgr = threading.Manager{};

pub var alloc: *memory.Allocator = undefined;
pub var big_alloc: *memory.Allocator = undefined;
pub var console: *Console = undefined;
pub var console_file = io.File{};
pub var raw_block_store: ?*io.BlockStore = null;
pub var block_store: io.CachedBlockStore = .{};
pub var filesystem: fs.Filesystem = .{};

pub fn platform_init() !void {
    print.init(&console_file, build_options.debug_log);
    try platform.init();
}

pub fn init() !void {
    try platform_init();

    // Filesystem
    if (raw_block_store) |raw| {
        block_store.use_direct = build_options.direct_disk;
        block_store.init(alloc, raw, 128);
        try filesystem.init(alloc, block_store.block_store);
    } else {
        print.string(" - No Disk Found\n");
    }
}

pub fn exec(info: *const georgios.ProcessInfo) georgios.ExecError!threading.Process.Id {
    const process = try threading_mgr.new_process(info);
    // print.format("exec: {}\n", .{info.path});
    var file = try filesystem.open(info.path);
    // TODO: better way to close the file!!
    defer filesystem.file_id_close(file.io_file.id.?) catch @panic("file_id_close");
    var elf_object = try elf.Object.from_file(alloc, big_alloc, &file.io_file);
    var segments = elf_object.segments.iterator();
    while (segments.next()) |segment| {
        switch (segment.what) {
            .Data => |data| try process.address_space_copy(segment.address, data),
            .UndefinedMemory => |size| try process.address_space_set(segment.address, 0, size),
        }
    }
    process.entry = elf_object.header.entry;
    try elf_object.teardown();
    try threading_mgr.start_process(process);
    return process.id;
}

pub fn run() !void {
    try init();
    print.string("\x1bc"); // Reset Console
    // try @import("sync.zig").system_tests();

    // Read and execute the path in the rc file
    var rc_file = try filesystem.open("/etc/rc");
    // TODO: better way to close the file!!
    defer filesystem.file_id_close(rc_file.io_file.id.?) catch @panic("file_id_close");
    var rc_buffer: [128]u8 = undefined;
    var rc_path: []const u8 = rc_buffer[0..try rc_file.io_file.read(rc_buffer[0..])];
    rc_path = rc_path[0..utils.stripped_string_size(rc_path)];
    threading_mgr.wait_for_process(try exec(&georgios.ProcessInfo{.path = rc_path}));
}

pub fn kernel_main() void {
    if (run()) |_| {} else |e| {
        panic(@errorName(e), @errorReturnTrace());
    }
    print.string("Done\n");
    platform.done();
}
