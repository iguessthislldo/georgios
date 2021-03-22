const system_calls = @import("system_calls");

export fn main() void {
    var c: usize = 0;
    while (true) {
        system_calls.print_string("a");
        c += 1;
        if (c == 100) {
            system_calls.yield();
            c = 0;
        }
    }
}
