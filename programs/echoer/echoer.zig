const system_calls = @import("common").system_calls;

export fn main() void {
    var buffer: [128]u8 = undefined;
    var got: usize = 0;
    while (true) {
        system_calls.print_string("? ");
        while (true) {
            const c = system_calls.getc();
            system_calls.print_string(@ptrCast([*]const u8, &c)[0..1]);
            if (c == '\n') {
                break;
            } else {
                buffer[got] = c;
                got += 1;
            }
        }
        if (got > 0) {
            system_calls.print_string("You entered ");
            system_calls.print_string(buffer[0..got]);
            system_calls.print_string("\n");
            got = 0;
        }
    }
}
