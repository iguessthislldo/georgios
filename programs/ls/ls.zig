const georgios = @import("georgios");
comptime {_ = georgios;}
const system_calls = georgios.system_calls;
const print_string = system_calls.print_string;

pub fn main() u8 {
    var path: []const u8 = ".";
    if (georgios.proc_info.args.len > 0) {
        path = georgios.proc_info.args[0];
    }

    var dir_file = georgios.fs.open(path, .{.ReadOnly = .{.dir = true}}) catch |e| {
        print_string("ls: open error: ");
        print_string(@errorName(e));
        print_string("\n");
        return 1;
    };
    defer dir_file.close() catch unreachable;

    var entry_buffer: [256]u8 = undefined;
    while (true) {
        const read = dir_file.read(entry_buffer[0..]) catch |e| {
            print_string("ls: read error: ");
            print_string(@errorName(e));
            print_string("\n");
            return 1;
        };
        if (read == 0) break;
        system_calls.print_string(entry_buffer[0..read]);
        system_calls.print_string("\n");
    }

    return 0;
}
