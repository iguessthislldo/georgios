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

fn main_wrapper() georgios.ExitInfo {
    var exit_info: georgios.ExitInfo = .{};
    const ret = @typeInfo(@typeInfo(@TypeOf(root.main)).Fn.return_type.?);
    switch (ret) {
        .Void => root.main(),
        .Int => exit_info.status = root.main(),
        .ErrorUnion => |eu| switch (@typeInfo(eu.payload)) {
            .Void => {
                if (root.main()) |_| {} else |e| {
                    @panic(@errorName(e));
                }
            },
            .Int => {
                if (root.main()) |status| {
                    exit_info.status = status;
                } else |e| {
                    @panic(@errorName(e));
                }
            },
            else => @compileError("main return type not supported"),
        },
        else => @compileError("main return type not supported"),
    }
    return exit_info;
}
