extern fn main() void;

export nakedcc fn main_wrapper() void {
    @setRuntimeSafety(false);
    asm volatile (
        \\movl $0xC0000000, %%esp
        );
    main();
}
