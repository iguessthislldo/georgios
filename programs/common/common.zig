extern fn main() void;

export fn main_wrapper() callconv(.Naked) void {
    @setRuntimeSafety(false);
    main();
}
