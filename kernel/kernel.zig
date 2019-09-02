const io = @import("io.zig");
const c = @cImport({
    @cInclude("memory.h");
    @cInclude("print.h");
});
const print_string = c.print_string;

pub export fn kernel_main() void {
    c.memory_init();
    io.initialize();

    print_string(c"Done\n");
    var value: u32 = 0;
    while (true) {
        value += 1;
    }
}
