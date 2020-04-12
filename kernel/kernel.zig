const builtin = @import("builtin");

const platform = @import("platform/platform.zig");
const print = @import("print.zig");
const Memory = @import("memory.zig").Memory;
const io = @import("io.zig");

pub var panic_message: []const u8 = "";

pub fn panic(msg: []const u8, trace: ?*builtin.StackTrace) noreturn {
    panic_message = msg;
    if (trace) |t| {
        print.format("index: {}\n", t.index);
        for (t.instruction_addresses) |addr| {
            if (addr == 0) break;
            print.format(" - {:x}\n", addr);
        }
    } else {
        print.string("No Stack Trace\n");
    }
    platform.panic(msg, trace);
}

pub const Kernel = struct {
    memory: Memory = Memory{},
    file_io: io.Files = io.Files{},
    console: ?*io.File = null,

    pub fn initialize(self: *Kernel) !void {
        try self.file_io.initialize();
        self.console = try self.file_io.new_file();
        print.initialize(self.console);
        try platform.initialize(self);
    }
};

pub export fn kernel_main() void {
    var kernel = Kernel{};
    if (kernel.initialize()) |_| {} else |e| {
        panic(@errorName(e), @errorReturnTrace());
    }
    print.string("Done\n");
}
