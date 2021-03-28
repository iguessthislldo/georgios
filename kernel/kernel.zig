const builtin = @import("builtin");
const build_options = @import("build_options");

pub const platform = @import("platform.zig");
pub const print = @import("print.zig");
pub const Memory = @import("memory.zig").Memory;
pub const io = @import("io.zig");
pub const elf = @import("elf.zig");
pub const util = @import("util.zig");
pub const Devices = @import("devices.zig").Devices;
pub const threading = @import("threading.zig");
pub const fs = @import("fs.zig");

pub var panic_message: []const u8 = "";

pub fn panic(msg: []const u8, trace: ?*builtin.StackTrace) noreturn {
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

pub var console: io.File = .{};
pub var memory: Memory = .{};
pub var devices: Devices = .{};
pub var raw_block_store: ?*io.BlockStore = null;
pub var block_store: io.CachedBlockStore = .{};
pub var filesystem: fs.Filesystem = .{};
pub var threading_manager: threading.Manager = undefined;

pub fn init() !void {
    print.init(&console, build_options.debug_log);
    try platform.init();

    // Filesystem
    if (raw_block_store) |raw| {
        block_store.init(memory.small_alloc, raw, 128);
        try filesystem.init(memory.small_alloc, &block_store.block_store);
    } else {
        print.string(" - No Disk Found\n");
    }

    // Threading
    threading_manager = threading.Manager{};
    try threading_manager.init();
}

fn exec(path: []const u8, kernel_mode: bool) !void {
    const process = try threading_manager.new_process(kernel_mode);
    var ext2_file = try filesystem.open(path);
    var elf_object = try elf.Object.from_file(memory.small_alloc, &ext2_file.io_file);
    var segments = elf_object.segments.iterator();
    while (segments.next()) |segment| {
        try process.address_space_copy(segment.address, segment.data);
    }
    process.entry = elf_object.header.entry;
    try threading_manager.start_process(process);
}

pub fn run() !void {
    try init();

    try exec("bin/a.elf", true);
    try exec("bin/b.elf", false);

    var c: usize = 0;
    while (true) {
        print.char('k');
        c += 1;
        if (c == 50) {
            threading_manager.yield();
            c = 0;
        }
    }
}

pub fn kernel_main() void {
    if (run()) |_| {} else |e| {
        panic(@errorName(e), @errorReturnTrace());
    }
    print.string("Done\n");
    platform.done();
}
