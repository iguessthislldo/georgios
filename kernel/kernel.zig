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

pub const Kernel = struct {
    console: io.File = io.File{},
    memory: Memory = Memory{},
    devices: Devices = Devices{},
    raw_block_store: ?*io.BlockStore = null,
    block_store: io.CachedBlockStore = io.CachedBlockStore{},
    filesystem: fs.Filesystem = fs.Filesystem{},
    threading_manager: threading.Manager = undefined,

    pub fn init(self: *Kernel) !void {
        print.init(&self.console, build_options.debug_log);
        try platform.init(self);

        // Filesystem
        if (self.raw_block_store) |raw| {
            self.block_store.init(self.memory.small_alloc, raw, 128);
            try self.filesystem.init(
                self.memory.small_alloc, &self.block_store.block_store);
        } else {
            print.string(" - No Disk Found\n");
        }

        // Threading
        self.threading_manager = threading.Manager{.memory_manager = &self.memory};
        try self.threading_manager.init();
    }

    fn exec(self: *Kernel, path: []const u8) !void {
        const process = try self.threading_manager.new_process(true);
        var ext2_file = try self.filesystem.open(path);
        var elf_object = try elf.Object.from_file(self.memory.small_alloc, &ext2_file.io_file);
        var segments = elf_object.segments.iterator();
        while (segments.next()) |segment| {
            try process.address_space_copy(segment.address, segment.data);
        }
        process.entry = elf_object.header.entry;
        try self.threading_manager.start_process(process);
    }

    pub fn run(self: *Kernel) !void {
        try self.init();

        try self.exec("bin/a.elf");
        try self.exec("bin/b.elf");

        var c: usize = 0;
        while (true) {
            print.char('k');
            c += 1;
            if (c == 50) {
                self.threading_manager.yield();
                c = 0;
            }
        }
    }
};

pub var kernel = Kernel{};

pub fn kernel_main() void {
    if (kernel.run()) |_| {} else |e| {
        panic(@errorName(e), @errorReturnTrace());
    }
    print.string("Done\n");
    platform.done();
}
