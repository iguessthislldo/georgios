pub const system_calls = @import("system_calls.zig");
pub const utils = @import("utils");

extern fn main() void;

export fn main_wrapper() callconv(.Naked) void {
    @setRuntimeSafety(false);
    main();
}
