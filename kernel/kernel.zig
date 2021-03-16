const builtin = @import("builtin");
const build_options = @import("build_options");

pub const platform = @import("platform.zig");
pub const print = @import("print.zig");
pub const Memory = @import("memory.zig").Memory;
pub const io = @import("io.zig");
pub const elf = @import("elf.zig");
pub const util = @import("util.zig");
pub const Ext2 = @import("ext2.zig").Ext2;
pub const Devices = @import("devices.zig").Devices;
pub const threading = @import("threading.zig");

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
    filesystem: Ext2 = Ext2{},
    threading_manager: threading.Manager = undefined,

    pub fn initialize(self: *Kernel) !void {
        print.initialize(&self.console, build_options.debug_log);
        try platform.initialize(self);
        if (self.raw_block_store) |raw| {
            self.block_store.init(self.memory.small_alloc, raw, 128);
            try self.filesystem.initialize(
                self.memory.small_alloc, &self.block_store.block_store);
        } else {
            print.string("No block store set\n");
        }
        self.threading_manager = threading.Manager{.memory_manager = &self.memory};
    }

    pub fn run(self: *Kernel) !void {
        try self.initialize();

        const a = try self.threading_manager.new_process();
        var ext2_file = try self.filesystem.open("a.elf");
        var elf_object = try elf.Object.from_file(self.memory.small_alloc, &ext2_file.io_file);
        // TODO: Function to set up a Process from an elf.Object
        try a.address_space_copy(elf_object.program_address, elf_object.program);
        a.entry = elf_object.header.entry;
        try self.threading_manager.start_process(a);
    }
};

var kernel = Kernel{};

pub fn kernel_main() void {
    if (kernel.run()) |_| {} else |e| {
        panic(@errorName(e), @errorReturnTrace());
    }
    print.string("Done\n");
    platform.done();
}
