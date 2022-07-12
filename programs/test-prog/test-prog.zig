const std = @import("std");
const georgios = @import("georgios");
comptime {_ = georgios;}
const streq = georgios.utils.memory_compare;
const system_calls = georgios.system_calls;
const print_string = system_calls.print_string;
const print_uint = system_calls.print_uint;

pub fn main() u8 {
    var exit_with = false;
    for (georgios.proc_info.args) |arg| {
        if (exit_with) {
            var status: u8 = 1;
            if (std.fmt.parseUnsigned(u8, arg, 10)) |int| {
                status = int;
            } else |err| {
                print_string("Invalid exit-with value: ");
                print_string(@errorName(err));
                print_string("\n");
            }
            return status;
        } else if (streq(arg, "exit-with")) {
            exit_with = true;
        } else {
            print_string("Invalid argument: ");
            print_string(arg);
            print_string("\n");
            return 1;
        }
    }

    return 0;
}
