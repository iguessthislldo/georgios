const io = @import("io.zig");
const util = @import("util.zig");
const KiB = util.KiB;
const c = @cImport({
    @cInclude("memory.h");
    @cInclude("print.h");
});
const print_string = c.print_string;

pub export fn kernel_main() void {
    c.memory_init();
    io.initialize();
    c.print_string(c"Booted\n");

    print_string(c"Done\n");
    var value: u32 = 0;
    while (true) {
        value += 1;
    }
}
