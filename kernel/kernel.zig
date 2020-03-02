const builtin = @import("builtin");

const platform = @import("platform/platform.zig");
const print = @import("print.zig");

pub export fn kernel_main() void {
    platform.initialize();

    print.string("Done\n");
}
