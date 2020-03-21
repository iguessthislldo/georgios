const builtin = @import("builtin");

const platform = @import("platform/platform.zig");
const print = @import("print.zig");

pub var panic_message: []const u8 = "";

pub fn panic(msg: []const u8, trace: ?*builtin.StackTrace) noreturn {
    platform.panic(msg, trace);
}

pub export fn kernel_main() void {
    platform.initialize();

    print.string("Done\n");
}
