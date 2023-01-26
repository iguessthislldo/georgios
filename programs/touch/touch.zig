const georgios = @import("georgios");
comptime {_ = georgios;}
const console = georgios.get_console_writer();

pub fn main() u8 {
    for (georgios.proc_info.args) |path| {
        var dir = georgios.Directory{._port_id = georgios.MetaPort};
        dir.create(path, .{.file = true}) catch |e| {
            try console.print("touch: error: {s}\n", .{@errorName(e)});
            return 1;
        };
    }

    return 0;
}
