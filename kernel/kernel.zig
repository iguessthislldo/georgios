const c = @cImport({
    @cInclude("memory.h");
});

export fn kernel_main() void {
    c.memory_init();
    var value: u32 = 0;
    while (true) {
        value += 1;
    }
}
