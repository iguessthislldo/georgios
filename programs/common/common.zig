extern fn main() void;

export fn main_wrapper() callconv(.Naked) void {
    @setRuntimeSafety(false);
    asm volatile (
        \\movl $0xC0000000, %%esp
        );
    main();
}
