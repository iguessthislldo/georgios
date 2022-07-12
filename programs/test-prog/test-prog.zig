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
        } else if (streq(arg, "panic")) {
            @panic("Panic was requested");
        } else if (streq(arg, "kpanic")) {
            // Try to invoke an interrupt that's only for the kernel.
            asm volatile ("int $50");
        } else if (streq(arg, "kcode")) {
            // Try to run code in kernel space
            asm volatile (
                \\pushl $0xc013bef0
                \\ret
            );
        } else if (streq(arg, "koverflow")) {
            system_calls.overflow_kernel_stack();
        } else {
            print_string("Invalid argument: ");
            print_string(arg);
            print_string("\n");
            return 1;
        }
    }

    return 0;
}
