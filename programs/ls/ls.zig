const georgios = @import("georgios");
comptime {_ = georgios;}
const console = georgios.get_console_writer();

pub fn main() u8 {
    var path: []const u8 = ".";
    if (georgios.proc_info.args.len > 0) {
        path = georgios.proc_info.args[0];
    }

    var dir_file = georgios.fs.open(path, .{.ReadOnly = .{.dir = true}}) catch |e| {
        try console.print("ls: open error: {s}\n", .{@errorName(e)});
        return 1;
    };
    defer dir_file.close() catch unreachable;

    var entry_buffer: [256]u8 = undefined;
    while (true) {
        const read = dir_file.read(entry_buffer[0..]) catch |e| {
            try console.print("ls: read error: {s}\n", .{@errorName(e)});
            return 1;
        };
        if (read == 0) break;
        try console.print("{s}\n", .{entry_buffer[0..read]});
    }

    return 0;
}
