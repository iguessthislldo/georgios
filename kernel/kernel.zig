const builtin = @import("builtin");
const build_options = @import("build_options");

pub const platform = @import("platform.zig");
pub const print = @import("print.zig");
pub const Memory = @import("memory.zig").Memory;
pub const io = @import("io.zig");
pub const elf = @import("elf.zig");
pub const util = @import("util.zig");
pub const Ext2 = @import("ext2.zig").Ext2;

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
    const Files = io.Files(32);

    memory: Memory = Memory{},
    file_io: Files = Files{},
    console: ?*io.File = null,

    pub fn initialize(self: *Kernel) !void {
        // Get the Console Ready
        try self.file_io.initialize();
        self.console = try self.file_io.new_file();
        print.initialize(self.console, build_options.debug_log);

        // Do a Whole Bunch of Stuff
        try platform.initialize(self);
    }

    pub fn run(self: *Kernel) !void {
        try self.initialize();

        var ext2 = Ext2{};
        try ext2.initialize(self.memory.kalloc);
        var ext2_file = try ext2.open("test_prog.elf");
        const file = &ext2_file.io_file;

        // var buffer: [512]u8 = undefined;
        // while (true) {
        //     const read_size = try file.read(buffer[0..]);
        //     print.format("read {}\n", read_size);
        //     if (read_size == 0) break;
        //     print.data_bytes(buffer[0..read_size]);
        // }

        var elf_object = try elf.Object.from_file(self.memory.kalloc, file);

        const Range = @import("memory.zig").Range;
        const range = Range{.start=0, .size=elf_object.program.len};
        try self.memory.platform_memory.mark_virtual_memory_present(range, true);
        var i: usize = 0;
        while (i < range.size) {
            @intToPtr(*allowzero u32, range.start + i).* = elf_object.program[i];
            i += 1;
        }
        // asm volatile ("jmp *%[entry_point]" :: [entry_point] "{eax}" (elf_object.header.entry));
        const usermode_stack = Range{
            .start = platform.impl.kernel_to_virtual(0) - platform.frame_size,
            .size = platform.frame_size};
        try self.memory.platform_memory.mark_virtual_memory_present(usermode_stack, true);
        const kernelmode_stack = try self.memory.platform_memory.get_kernel_space(util.Ki(4));
        platform.impl.segments.set_usermode_interrupt_stack(kernelmode_stack.end() - 1);
        usermode(elf_object.header.entry, usermode_stack.end());
    }
};

pub export fn kernel_main() void {
    panic_message = ""; // TODO: This is garbage when a panic happens
    var kernel = Kernel{};
    if (kernel.run()) |_| {} else |e| {
        panic(@errorName(e), @errorReturnTrace());
    }
    print.string("Done\n");
    platform.done();
}
