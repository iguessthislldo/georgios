const georgios = @import("georgios");
comptime {_ = georgios;}
const system_calls = georgios.system_calls;
const print_string = system_calls.print_string;

pub fn main() u8 {
    for (georgios.proc_info.args) |arg| {
        var file = georgios.fs.open(arg, .{.ReadOnly = .{}}) catch |e| {
            print_string("cat: open error: ");
            print_string(@errorName(e));
            print_string("\n");
            return 1;
        };

        var buffer: [128]u8 = undefined;
        var got: usize = 1;
        while (got > 0) {
            if (file.read(buffer[0..])) |g| {
                got = g;
            } else |e| {
                print_string("cat: file.read error: ");
                print_string(@errorName(e));
                print_string("\n");
                return 1;
            }
            if (got > 0) {
                print_string(buffer[0..got]);
            }
        }

        file.close() catch |e| {
            print_string("cat: file.close error: ");
            print_string(@errorName(e));
            print_string("\n");
            return 1;
        };
    }

    return 0;
}
