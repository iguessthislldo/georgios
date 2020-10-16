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

pub var panic_message: []const u8 = "";

pub fn panic(msg: []const u8, trace: ?*builtin.StackTrace) noreturn {
    panic_message = msg;
    if (trace) |t| {
        print.format("index: {}\n", t.index);
        for (t.instruction_addresses) |addr| {
            if (addr == 0) break;
            print.format(" - {:a}\n", addr);
        }
    } else {
        print.string("No Stack Trace\n");
    }
    platform.panic(msg, trace);
}

extern fn usermode(ip: u32, sp: u32) noreturn;

pub const Kernel = struct {
    console: io.File = io.File{},
    memory: Memory = Memory{},
    devices: Devices = Devices{},
    raw_block_store: ?*io.BlockStore = null,
    block_store: io.CachedBlockStore = io.CachedBlockStore{},
    filesystem: Ext2 = Ext2{},

    pub fn initialize(self: *Kernel) !void {
        print.initialize(&self.console, build_options.debug_log);
        try platform.initialize(self);
        if (self.raw_block_store) |raw| {
            self.block_store.init(self.memory.small_alloc, raw, 128);
            try self.filesystem.initialize(self.memory.small_alloc, &self.block_store.block_store);
        } else {
            print.format("No block store set\n");
        }
    }

    pub fn run(self: *Kernel) !void {
        try self.initialize();

        var ext2_file = try self.filesystem.open("echoer.elf");
        const file = &ext2_file.io_file;
        var elf_object = try elf.Object.from_file(self.memory.small_alloc, file);
        const Range = @import("memory.zig").Range;
        const range = Range{.start=0, .size=elf_object.program.len};
        try self.memory.platform_memory.mark_virtual_memory_present(range, true);
        var i: usize = 0;
        while (i < range.size) {
            @intToPtr(*allowzero u32, range.start + i).* = elf_object.program[i];
            i += 1;
        }
        const usermode_stack = Range{
            .start = platform.impl.kernel_to_virtual(0) - platform.frame_size,
            .size = platform.frame_size};
        try self.memory.platform_memory.mark_virtual_memory_present(usermode_stack, true);
        const kernelmode_stack = try self.memory.big_alloc.alloc_range(util.Ki(4));
        platform.impl.segments.set_usermode_interrupt_stack(kernelmode_stack.end() - 1);
        usermode(elf_object.header.entry, usermode_stack.end());
    }
};

var kernel = Kernel{};

pub export fn kernel_main() void {
    if (kernel.run()) |_| {} else |e| {
        panic(@errorName(e), @errorReturnTrace());
    }
    print.string("Done\n");
    platform.done();
}
