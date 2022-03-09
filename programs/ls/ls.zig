const georgios = @import("georgios");
comptime {_ = georgios;}
const system_calls = georgios.system_calls;

pub fn main() void {
    var path: []const u8 = ".";
    if (georgios.proc_info.args.len > 0) {
        path = georgios.proc_info.args[0];
    }
    var dir_entry = georgios.DirEntry{.dir = path};
    if (system_calls.next_dir_entry(&dir_entry)) {
        system_calls.print_string("Failed\n");
        system_calls.exit(1);
    }
    while (!dir_entry.done) {
        system_calls.print_string(dir_entry.current_entry);
        system_calls.print_string("\n");
        if (system_calls.next_dir_entry(&dir_entry)) {
            system_calls.print_string("Failed in middle of listing?\n");
            system_calls.exit(1);
        }
    }
}
