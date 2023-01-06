const std = @import("std");
const georgios = @import("georgios");
comptime {_ = georgios;}
const streq = georgios.utils.memory_compare;
const system_calls = georgios.system_calls;

const console = georgios.get_console_writer();

extern var _end: u32;

pub fn main() !u8 {
    var exit_with = false;
    for (georgios.proc_info.args) |arg| {
        if (exit_with) {
            var status: u8 = 1;
            if (std.fmt.parseUnsigned(u8, arg, 10)) |int| {
                status = int;
            } else |err| {
                try console.print("Invalid exit-with value \"{s}\": {s}\n", .{arg, @errorName(err)});
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
        } else if (streq(arg, "mem")) {
            try console.print("_end = {x}\n", .{@ptrToInt(&_end)});
            _ = try system_calls.add_dynamic_memory(4);
            _end = 10;
        } else if (streq(arg, "mem-segfault")) {
            try console.print("_end = {x}\n", .{@ptrToInt(&_end)});
            _end = 10;
        } else if (streq(arg, "mem-fail")) {
            _ = try system_calls.add_dynamic_memory(std.math.maxInt(usize));
        } else if (streq(arg, "mem-fill")) {
            // TODO: Figure out why this fails with missing page after a while.
            try console.print("_end = {x}\n", .{@ptrToInt(&_end)});
            while (true) {
                const area = try system_calls.add_dynamic_memory(4096);
                const end = @ptrToInt(area.ptr) + area.len;
                try console.print("{x}\n", .{end});
                @intToPtr(*u8, end - 1).* = 0xff;
            }
        } else {
            try console.print("Invalid argument: {s}\n", .{arg});
            return 1;
        }
    }

    return 0;
}
