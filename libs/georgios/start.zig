const root = @import("root");

const system_calls = @import("system_calls.zig");
const georgios = @import("georgios.zig");

export fn _start() callconv(.Naked) noreturn {
    georgios.proc_info = asm volatile ("xor %%ebp, %%ebp" :
        [info] "={esp}" (-> *const georgios.ProcessInfo));
    @call(.{ .modifier = .never_inline }, start, .{});
}

fn start() noreturn {
    system_calls.exit(main_wrapper());
}

fn main_wrapper() u8 {
    var exit_status: u8 = 0;
    switch (@typeInfo(@typeInfo(@TypeOf(root.main)).Fn.return_type.?)) {
        .Void => root.main(),
        .Int => exit_status = root.main(),
        else => @compileError("main return type not supported"),
    }
    return exit_status;
}
