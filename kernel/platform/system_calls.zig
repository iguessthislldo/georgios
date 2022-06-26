// System Call Handling

const utils = @import("utils");
const georgios = @import("georgios");

const kernel = @import("root").kernel;
const print = kernel.print;
const kthreading = kernel.threading;

const ps2 = @import("ps2.zig");
const interrupts = @import("interrupts.zig");
const vbe = @import("vbe.zig");

pub const interrupt_number: u8 = 100;

pub fn handle(_: u32, interrupt_stack: *const interrupts.Stack) void {
    const call_number = interrupt_stack.eax;
    const arg1 = interrupt_stack.ebx;
    const arg2 = interrupt_stack.ecx;
    const arg3 = interrupt_stack.edx;
    const arg4 = interrupt_stack.edi;
    _ = arg4;
    const arg5 = interrupt_stack.esi;
    _ = arg5;

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
        // - One is a & before names of arguments intended to be passed to the
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
        // System calls that return Zig errors should use ValueOrError and must
        // set something. This type exists because Zig errors can only safely
        // be used within the same compilation. To get around that this type
        // translates the kernel Zig errors to ABI-stable values to pass across
        // the system call boundary. In user space, the same type tries to
        // translate the values back to Zig errors. If the kernel error type is
        // unknown to the user program it gets the utils.Error.Unknown error.
        //
        // The following must come after a SYSCALL comment and before the
        // system call implementation:
        //
        // - An IMPORT comment will combine with other system call imports and
        //   import Zig namespace needed for the system calls arguments and
        //   return.
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
            kernel.threading_mgr.yield();
        },

        // SYSCALL: exit(status: u8) noreturn
        3 => {
            // TODO: Use status
            if (kthreading.debug) print.string("\nE");
            kernel.threading_mgr.remove_current_thread();
        },

        // SYSCALL: exec(info: *const georgios.ProcessInfo) georgios.ExecError!void
        // IMPORT: georgios "georgios.zig"
        4 => {
            const ValueOrError = georgios.system_calls.ValueOrError(void, georgios.ExecError);
            // Should not be able to create kernel mode process from a system
            // call that can be called from user mode.
            var info = @intToPtr(*const georgios.ProcessInfo, arg1).*;
            info.kernel_mode = false;
            const rv = @intToPtr(*ValueOrError, arg2);
            if (kernel.exec(&info)) |pid| {
                kernel.threading_mgr.wait_for_process(pid);
                rv.set_value(.{});
            } else |e| {
                rv.set_error(e);
            }
        },

        // SYSCALL: get_key(&blocking: georgios.Blocking) key: ?georgios.keyboard.Event
        // IMPORT: georgios "georgios.zig"
        5 => {
            const blocking = @intToPtr(*georgios.Blocking, arg1).* == .Blocking;
            const rv = @intToPtr(*?georgios.keyboard.Event, arg2);
            while (true) {
                if (ps2.get_key()) |key| {
                    rv.* = key;
                    break;
                } else if (blocking) {
                    kernel.threading_mgr.wait_for_keyboard();
                } else {
                    rv.* = null;
                    break;
                }
            }
        },

        // TODO: Return Zig Error
        // SYSCALL: next_dir_entry(iter: *georgios.DirEntry) bool
        // IMPORT: georgios "georgios.zig"
        6 => {
            const entry = @intToPtr(*georgios.DirEntry, arg1);
            const failure_ptr = @intToPtr(*bool, arg2);
            failure_ptr.* = false;
            kernel.filesystem.impl.next_dir_entry(entry) catch |e| {
                print.format("next_dir_entry failed in dir {}: {}\n", .{entry.dir, @errorName(e)});
                failure_ptr.* = true;
                return;
            };
        },

        // SYSCALL: print_uint(value: u32, base: u8) void
        7 => {
            switch (arg2) {
                16 => print.hex(arg1),
                else => print.uint(arg1),
            }
        },

        // SYSCALL: file_open(&path: []const u8) georgios.fs.Error!georgios.io.File.Id
        8 => {
            const ValueOrError = georgios.system_calls.ValueOrError(
                georgios.io.File.Id, georgios.fs.Error);
            const path = @intToPtr(*[]const u8, arg1);
            const rv = @intToPtr(*ValueOrError, arg2);
            if (kernel.filesystem.open(path.*)) |fs_file| {
                rv.set_value(fs_file.io_file.id.?);
            } else |e| {
                rv.set_error(e);
            }
        },

        // SYSCALL: file_read(id: georgios.io.File.Id, &to: []u8) georgios.io.FileError!usize
        9 => {
            const ValueOrError = georgios.system_calls.ValueOrError(
                usize, georgios.io.FileError);
            const id = arg1;
            const to = @intToPtr(*[]u8, arg2);
            const rv = @intToPtr(*ValueOrError, arg3);
            if (kernel.filesystem.file_id_read(id, to.*)) |read| {
                rv.set_value(read);
            } else |e| {
                rv.set_error(e);
            }
        },

        // SYSCALL: file_write(id: georgios.io.File.Id, &from: []const u8) georgios.io.FileError!usize
        10 => {
            const ValueOrError = georgios.system_calls.ValueOrError(
                usize, georgios.io.FileError);
            const id = arg1;
            const from = @intToPtr(*[]const u8, arg2);
            const rv = @intToPtr(*ValueOrError, arg3);
            if (kernel.filesystem.file_id_write(id, from.*)) |written| {
                rv.set_value(written);
            } else |e| {
                rv.set_error(e);
            }
        },

        // SYSCALL: file_seek(id: georgios.io.File.Id, offset: isize, seek_type: georgios.io.File.SeekType) georgios.io.FileError!usize
        11 => {
            // TODO
            @panic("file_seek called");
        },


        // SYSCALL: file_close(id: georgios.io.File.Id) georgios.io.FileError!void
        12 => {
            const ValueOrError = georgios.system_calls.ValueOrError(
                void, georgios.io.FileError);
            const id = arg1;
            const rv = @intToPtr(*ValueOrError, arg2);
            if (kernel.filesystem.file_id_close(id)) {
                rv.set_value(.{});
            } else |e| {
                rv.set_error(e);
            }
        },

        // SYSCALL: get_cwd(&buffer: []u8) georgios.threading.Error![]const u8
        13 => {
            const ValueOrError = georgios.system_calls.ValueOrError(
                []const u8, georgios.threading.Error);
            const buffer = @intToPtr(*[]u8, arg1).*;
            const rv = @intToPtr(*ValueOrError, arg2);
            if (kernel.threading_mgr.get_cwd(buffer)) |dir| {
                rv.set_value(dir);
            } else |e| {
                rv.set_error(e);
            }
        },

        // SYSCALL: set_cwd(&dir: []const u8) georgios.ThreadingOrFsError!void
        14 => {
            const ValueOrError = georgios.system_calls.ValueOrError(
                void, georgios.ThreadingOrFsError);
            const dir = @intToPtr(*[]const u8, arg1).*;
            const rv = @intToPtr(*ValueOrError, arg2);
            if (kernel.threading_mgr.set_cwd(dir)) {
                rv.set_value(.{});
            } else |e| {
                rv.set_error(e);
            }
        },

        // SYSCALL: sleep_milliseconds(&ms: u64) void
        15 => {
            kernel.threading_mgr.sleep_milliseconds(@intToPtr(*u64, arg1).*);
        },

        // SYSCALL: sleep_seconds(&s: u64) void
        16 => {
            kernel.threading_mgr.sleep_seconds(@intToPtr(*u64, arg1).*);
        },

        // SYSCALL: time() u64
        17 => {
            @intToPtr(*u64, arg1).* = kernel.platform.time();
        },

        // SYSCALL: get_process_id() u32
        18 => {
            const r = @intToPtr(*u32, arg1);
            if (kernel.threading_mgr.current_process) |p| {
                r.* = p.id;
            } else {
                r.* = 0;
            }
        },

        // SYSCALL: get_thread_id() u32
        19 => {
            const r = @intToPtr(*u32, arg1);
            if (kernel.threading_mgr.current_thread) |t| {
                r.* = t.id;
            } else {
                r.* = 0;
            }
        },

        // SYSCALL: overflow_kernel_stack() void
        20 => {
            overflow_kernel_stack();
        },

        // SYSCALL: console_width() u32
        21 => {
            const r = @intToPtr(*u32, arg1);
            r.* = kernel.console.width;
        },

        // SYSCALL: console_height() u32
        22 => {
            const r = @intToPtr(*u32, arg1);
            r.* = kernel.console.height;
        },

        // SYSCALL: vbe_res() ?utils.Point
        23 => {
            const rv = @intToPtr(*?utils.Point, arg1);
            rv.* = vbe.get_res();
        },

        // SYSCALL: vbe_draw_raw_image_chunk(&data: []const u8, w: u32, &pos: utils.Point, &last: utils.Point) void
        24 => {
            const data = @intToPtr(*[]const u8, arg1).*;
            const width = arg2;
            const pos = @intToPtr(*utils.Point, arg3);
            const last = @intToPtr(*utils.Point, arg4);
            vbe.draw_raw_image_chunk(data, width, pos, last);
        },

        // SYSCALL: vbe_flush_buffer() void
        25 => {
            vbe.flush_buffer();
        },

        else => @panic("Invalid System Call"),
    }
}

fn overflow_kernel_stack() void {
    if (kernel.threading_mgr.current_thread) |thread| {
        print.format("kernelmode_stack: {:a} - {:a}", .{
            thread.impl.kernelmode_stack.start,
            thread.impl.kernelmode_stack.end(),
        });
    }
    overflow_kernel_stack_i();
}

fn overflow_kernel_stack_i() void {
    var use_to_find_guard_page: [128]u8 = undefined;
    print.format("overflow_kernel_stack: esp: {:a}\n", .{
        asm volatile ("mov %%esp, %[x]" : [x] "=r" (-> usize))});
    for (use_to_find_guard_page) |*ptr, i| {
        ptr.* = @truncate(u8, i);
    }
    overflow_kernel_stack_i();
}
