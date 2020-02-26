const builtin = @import("builtin");

const c = @cImport({
    @cInclude("kernel.h");
    @cInclude("print.h");
});

pub fn panic(msg: []const u8, trace: ?*builtin.StackTrace) noreturn {
    c.set_panic_message(&msg[0], msg.len);
    if (trace) |t| {
        c.print_format(c"index: {d}\n", t.index);
        for (t.instruction_addresses) |addr| {
            c.print_format(c" - {x}\n", addr);
        }
    } else {
        c.print_string(c"No Stack Trace\n");
    }
    asm volatile ("pushl $0\n\tint $50");
    unreachable;
}
