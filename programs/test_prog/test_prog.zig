const system_calls = @import("system_calls");

export fn main() void {
    while (true) {
        system_calls.print_char('+');
        system_calls.print_char('-');
    }
}
