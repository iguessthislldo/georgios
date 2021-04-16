// System Call Handling

const utils = @import("utils");
const georgios = @import("georgios");

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

        // SYSCALL: yield() void
        2 => {
            if (kthreading.debug) print.string("\nY");
            kernel.threading_manager.yield();
        },

        // SYSCALL: exit(status: u8) noreturn
        3 => {
            // TODO: Use status
            if (kthreading.debug) print.string("\nE");
            kernel.threading_manager.remove_current_thread();
        },

        // SYSCALL: exec(info: *const georgios.ProcessInfo) failure: bool
        // IMPORT: georgios "georgios.zig"
        4 => {
            var info = @intToPtr(*const georgios.ProcessInfo, arg1).*;
            info.kernel_mode = false;
            const failure_ptr = @intToPtr(*bool, arg2);
            failure_ptr.* = false;
            const pid = kernel.exec(&info) catch |e| {
                print.format("exec failed: {}\n", .{@errorName(e)});
                failure_ptr.* = true;
                return;
            };
            kernel.threading_manager.wait_for_process(pid);
        },

        // SYSCALL: get_key() key: georgios.keyboard.Event
        // IMPORT: georgios "georgios.zig"
        5 => {
            while (true) {
                if (ps2.get_key()) |key| {
                    @intToPtr(*georgios.keyboard.Event, arg1).* = key;
                    break;
                }
                kernel.threading_manager.wait_for_keyboard();
            }
        },

        // SYSCALL: next_dir_entry(iter: *georgios.DirEntry) bool
        // IMPORT: georgios "georgios.zig"
        6 => {
            const failure_ptr = @intToPtr(*bool, arg2);
            failure_ptr.* = false;
            kernel.filesystem.impl.next_dir_entry(
                    @intToPtr(*georgios.DirEntry, arg1)) catch |e| {
                print.format("next_dir_iter failed: {}\n", .{@errorName(e)});
                failure_ptr.* = true;
                return;
            };
        },

        // SYSCALL: print_hex(value: u32) void
        7 => print.hex(arg1),

        // SYSCALL: file_open(&path: []const u8) georgios.fs.Error!georgios.io.File.Id
        8 => {
            const path = @intToPtr(*[]const u8, arg1);
            const rv = @intToPtr(*georgios.fs.Error!georgios.io.File.Id, arg2);
            const fs_file = kernel.filesystem.open(path.*) catch |e| {
                rv.* = e;
                return;
            };
            rv.* = fs_file.io_file.id.?;
        },

        // SYSCALL: file_read(id: georgios.io.File.Id, &to: []u8) georgios.io.FileError!usize
        9 => {
            const id = arg1;
            const to = @intToPtr(*[]u8, arg2);
            const rv = @intToPtr(*georgios.io.FileError!usize, arg3);
            rv.* = kernel.filesystem.file_id_read(id, to.*);
        },

        // SYSCALL: file_close(id: georgios.io.File.Id) georgios.io.FileError!void
        10 => {
            const id = arg1;
            const rv = @intToPtr(*georgios.io.FileError!void, arg2);
            rv.* = kernel.filesystem.file_id_close(id);
        },

        else => @panic("Invalid System Call"),
    }
}
