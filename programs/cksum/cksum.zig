const georgios = @import("georgios");
comptime {_ = georgios;}
const Cksum = georgios.utils.Cksum;
const system_calls = georgios.system_calls;
const print_string = system_calls.print_string;

var buffer: [128]u8 = undefined;

fn print_result(filename: []const u8, cksum: *Cksum) !void {
    var ts = georgios.utils.ToString{.buffer = buffer[0..]};
    try ts.uint(cksum.get_result());
    try ts.char(' ');
    try ts.uint(cksum.total_size);
    try ts.char(' ');
    try ts.string(filename);
    try ts.char('\n');
    print_string(ts.get());
}

pub fn main() void {
    for (georgios.proc_info.args) |arg| {
        var cksum = georgios.utils.Cksum{};
        var file = georgios.fs.open(arg) catch |e| {
            print_string("cksum: open error: ");
            print_string(@errorName(e));
            print_string("\n");
            return;
        };

        var got: usize = 1;
        while (got > 0) {
            if (file.read(buffer[0..])) |g| {
                got = g;
            } else |e| {
                print_string("cksum: file.read error: ");
                print_string(@errorName(e));
                print_string("\n");
                got = 0;
            }
            if (got > 0) {
                cksum.sum_bytes(buffer[0..got]);
            }
        }
        
        print_result(arg, &cksum) catch |e| {
            print_string("cksum: failed to print result: ");
            print_string(@errorName(e));
            print_string("\n");
            return;
        };

        file.close() catch |e| {
            print_string("cksum: file.close error: ");
            print_string(@errorName(e));
            print_string("\n");
            return;
        };
    }
}
