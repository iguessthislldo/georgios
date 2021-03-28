const system_calls = @import("system_calls");

export fn main() void {
    var c1: usize = 0;
    var c2: usize = 0;
    while (c2 < 15) {
        system_calls.print_string("b");
        c1 += 1;
        if (c1 == 100) {
            c1 = 0;
            c2 += 1;
            // system_calls.yield();
        }
    }
    system_calls.print_string("b about to exit");
    system_calls.exit(0);
}
