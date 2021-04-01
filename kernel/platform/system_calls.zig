// System Call Handling

const utils = @import("utils");

const kernel = @import("../kernel.zig");
const print = @import("../print.zig");
const kthreading = @import("../threading.zig");

const ps2 = @import("ps2.zig");
const interrupts = @import("interrupts.zig");

pub const interrupt_number: u8 = 100;

pub fn handle(_: u32, interrupt_stack: *const interrupts.Stack) void {
    const call_number = interrupt_stack.eax;
    const arg1 = interrupt_stack.ebx;
    const arg2 = interrupt_stack.ecx;
    const arg3 = interrupt_stack.edx;

    // TODO: Using pointers for args can cause Zig's alignment checks to fail.
    // Find a way around this without turning off safety?
    @setRuntimeSafety(false);

    switch (call_number) {
        // This file is parsed by generate_system_calls.py to generate the
        // system call interface functions used by programs. Before a system
        // call implementation there should be a SYSCALL comment with something
        // like the intended Zig signature in it. This pseudo-signature is the
        // same as normal, but with 2 differences:
        //
        // - One is a & before names of arguments indented to be passed to the
        //   system call implementation as pointers. This is necessary for things
        //   larger than a register.
        //   Example: \\ SYSCALL: cool_syscall(&cool_arg: []const u8) void
        //
        // - The other is an optional name after the arguments that sets the name
        //   of the return value in the generated function.
        //   Example: \\ SYSCALL: cool_syscall() cool_return: u32`
        //
        // What registers the arguments and return values use depend on the
        // argN constants above and the order they appear in the signature.
        // Example: \\ SYSCALL: cool_syscall(a: u32, b: u32) c: u32
        // a should be read from arg1, b should be read from arg2, and the
        // return value should be written to arg3.
        //
        // The following must come after a SYSCALL comment and before the
        // system call implementation:
        //
        // - An IMPORT comment will combine with other system call imports and
        //   import Zig namespace needed for the system calls.
        //   arguments and return.
        //   Example: \\ IMPORT: cool "cool"
        //   Will insert: const cool = @import("cool")
        //
        // TODO: Documentation Comments
        // TODO: C alternative interface syscalls?

        // SYSCALL: print_string(&s: []const u8) void
        0 => print.string(@intToPtr(*[]const u8, arg1).*),

        // SYSCALL: getc() c: u8
        1 => {
            while (true) {
                if (ps2.get_char()) |c| {
                    @intToPtr(*u8, arg1).* = c;
                    break;
                }
                kernel.threading_manager.yield();
            }
        },

        // SYSCALL: yield() void
        2 => {
            if (kthreading.debug) print.string("\nY");
            kernel.threading_manager.yield();
        },

        // SYSCALL: exit(status: u8) void
        3 => {
            // TODO: Use status
            if (kthreading.debug) print.string("\nE");
            kernel.threading_manager.remove_current_thread();
        },

        // SYSCALL: exec(&path: []const u8) failure: bool
        4 => {
            @intToPtr(*bool, arg2).* = false;
            const pid = kernel.exec(@intToPtr(*[]const u8, arg1).*, false) catch |e| {
                print.format("exec failed: {}\n", .{@errorName(e)});
                @intToPtr(*bool, arg2).* = true;
                return;
            };
            kernel.threading_manager.yield_while_process_is_running(pid);
        },

        // SYSCALL: get_key() key: utils.Key
        // IMPORT: utils "utils"
        5 => {
            while (true) {
                if (ps2.get_key()) |key| {
                    @intToPtr(*utils.Key, arg1).* = key;
                    break;
                }
                kernel.threading_manager.yield();
            }
        },

        else => @panic("Invalid System Call"),
    }
}
