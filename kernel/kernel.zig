const builtin = @import("builtin");

const io = @import("io.zig");
const c = @cImport({
    @cInclude("kernel.h");
    @cInclude("memory.h");
    @cInclude("print.h");
});
const print_string = c.print_string;
const platform_panic = @import("platform/panic.zig").panic;

pub export fn kernel_main() void {
    c.memory_init();
    io.initialize();


pub fn panic(msg: []const u8, trace: ?*builtin.StackTrace) noreturn {
    platform_panic(msg, trace);
}
