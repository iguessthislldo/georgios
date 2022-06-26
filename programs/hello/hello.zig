const georgios = @import("georgios");
comptime {_ = georgios;}
const system_calls = georgios.system_calls;
const print_string = system_calls.print_string;
const print_uint = system_calls.print_uint;

pub fn main() void {
    print_string("program path is ");
    print_string(georgios.proc_info.path);
    print_string("\nprogram name is ");
    print_string(georgios.proc_info.name);
    print_string("\n");
    print_uint(georgios.proc_info.args.len, 10);
    print_string(" args\n");
    for (georgios.proc_info.args) |arg| {
        print_string("arg: \"");
        print_string(arg);
        print_string("\"\n");
    }
    print_string("Hello, World!\n");
}
