const std = @import("std");

const georgios = @import("georgios");
comptime {_ = georgios;}
const system_calls = georgios.system_calls;
const utils = georgios.utils;
const streq = utils.memory_compare;
const TinyishLisp = @import("TinyishLisp");
const Expr = TinyishLisp.Expr;

const print_string = system_calls.print_string;
const print_uint = system_calls.print_uint;

pub fn panic(msg: []const u8, trace: ?*std.builtin.StackTrace) noreturn {
    georgios.panic(msg, trace);
}

const segment_start = "░▒▓";
const segment_end = "▓▒░";
const esc = "\x1b";
const reset_console = esc ++ "c";
const ansi_esc = esc ++ "[";
const invert_colors = ansi_esc ++ "7m";
const reset_colors = ansi_esc ++ "39;49m";

const no_max = std.math.maxInt(usize);

var alloc: std.mem.Allocator = undefined;

var img_buffer: [2048]u8 align(@alignOf(u64)) = undefined;

var tl: TinyishLisp = undefined;
var custom_commands: std.StringHashMap(*Expr) = undefined;

var console = georgios.get_console_writer();
var generic_console_impl = utils.GenericWriterImpl(georgios.ConsoleWriter.Writer){};
var generic_console: utils.GenericWriter.Writer = undefined;

fn draw_dragon(t: *TinyishLisp) TinyishLisp.Error!*Expr {
    if (system_calls.vbe_res()) |res| {
        var file = georgios.fs.open("/files/dragon.img", .{.ReadOnly = .{}}) catch |e| {
            try console.print("shell: dragon open file error: {s}\n", .{@errorName(e)});
            return t.err;
        };
        var img = georgios.ImgFile{.file = &file, .buffer = img_buffer[0..]};
        img.parse_header() catch |e| {
            try console.print("shell: dragon invalid image file: {s}\n", .{@errorName(e)});
            return t.err;
        };

        img.draw(.{.x = res.x - img.size.?.x - 10, .y = 10}) catch |e| {
            try console.print("shell: dragon draw error: {s}\n", .{@errorName(e)});
            return t.err;
        };
        system_calls.vbe_flush_buffer();

        file.close() catch |e| {
            try console.print("shell: dragon file.close error: {s}\n", .{@errorName(e)});
            return t.err;
        };
    }

    return t.nil;
}

fn check_bin_path(path: []const u8, name: []const u8, buffer: []u8) ?[]const u8 {
    var dir_file = georgios.fs.open(path, .{.ReadOnly = .{.dir = true}}) catch |e| {
        try console.print("shell: check_bin_path open error: {s}\n", .{@errorName(e)});
        return null;
    };
    defer dir_file.close() catch unreachable;
    var pos = utils.memory_copy_truncate(buffer[0..], name);
    pos = pos + utils.memory_copy_truncate(buffer[pos..], ".elf");
    var entry_buffer: [256]u8 = undefined;
    while (true) {
        const read = dir_file.read(entry_buffer[0..]) catch |e| {
            try console.print("shell: check_bin_path read error: {s}\n", .{@errorName(e)});
            return null;
        };
        if (read == 0) break;
        const entry = entry_buffer[0..read];
        if (streq(entry, buffer[0..pos])) {
            pos = 0;
            pos = utils.memory_copy_truncate(buffer, path);
            pos = pos + utils.memory_copy_truncate(buffer[pos..], "/");
            pos = pos + utils.memory_copy_truncate(buffer[pos..], entry);
            return buffer[0..pos];
        }
    }
    return null;
}

var cwd_buffer: [128]u8 = undefined;
var command_parts: [32][]const u8 = undefined;
const max_command_len = 128;
var command_buffer: [max_command_len]u8 = undefined;
var processed_command_buffer: [max_command_len]u8 = undefined;

fn run_command(command: []const u8) bool {
    // Turn command into command_parts
    var it = georgios.utils.WordIterator{
        .quote = '\'', .input = command,
        .buffer = processed_command_buffer[0..],
    };
    var processed_command_buffer_offset: usize = 0;
    var command_part_count: usize = 0;
    while (it.next() catch @panic("command iter failure")) |part| {
        command_parts[command_part_count] = part;
        command_part_count += 1;
        processed_command_buffer_offset += part.len;
        it.buffer = processed_command_buffer[processed_command_buffer_offset..];
    }
    if (command_part_count == 0) {
        return false;
    }

    // Process command_parts
    if (streq(command_parts[0], "exit")) {
        return true;
    } else if (streq(command_parts[0], "reset")) {
        _ = try console.write(reset_console);
    } else if (streq(command_parts[0], "pwd")) {
        if (system_calls.get_cwd(cwd_buffer[0..])) |dir| {
            try console.print("{s}\n", .{dir});
        } else |e| {
            try console.print("Couldn't get current working directory: {s}\n", .{@errorName(e)});
        }
    } else if (streq(command_parts[0], "cd")) {
        if (command_part_count != 2) {
            _ = try console.write("cd requires exactly one argument\n");
        } else {
            system_calls.set_cwd(command_parts[1]) catch |e| {
                try console.print("Couldn't change current working directory to \"{s}\": {s}\n",
                    .{command_parts[1], @errorName(e)});
            };
        }
    } else if (streq(command_parts[0], "sleep")) {
        if (command_part_count != 2) {
            _ = try console.write("sleep requires exactly one argument\n");
        } else {
            if (std.fmt.parseUnsigned(usize, command_parts[1], 10)) |n| {
                system_calls.sleep_seconds(n);
            } else |e| {
                try console.print("invalid argument: {s}\n", .{@errorName(e)});
            }
        }
    } else if (custom_commands.get(command_parts[0])) |command_expr| {
        const args = tl.make_string_list(command_parts[1..], .Copy) catch |e| {
            try console.print("issue with converting args for custom command: {s}\n",
                .{@errorName(e)});
            return false;
        };
        const lisp_command = tl.cons(command_expr, args) catch |e| {
            try console.print("issue with making lisp command: {s}\n", .{@errorName(e)});
            return false;
        };
        print_lisp_result(tl.eval(lisp_command, tl.global_env) catch |e| {
            try console.print("issue with running lisp command: {s}\n", .{@errorName(e)});
            return false;
        });
    } else {
        var command_path = command_parts[0];
        var path_buffer: [128]u8 = undefined;
        if (check_bin_path("/bin", command_parts[0], path_buffer[0..])) |path| {
            command_path = path[0..];
        }
        const exit_info = system_calls.exec(&georgios.ProcessInfo{
            .path = command_path,
            .name = command_parts[0],
            .args = command_parts[1..command_part_count],
        }) catch |e| {
            try console.print("Command \"{s}\" failed: {s}\n", .{command, @errorName(e)});
            return false;
        };
        if (exit_info.failed()) {
            // Start
            print_string(
                ansi_esc ++ "31m" ++ // Red FG
                segment_start ++ reset_colors);

            // Status
            print_string(ansi_esc ++ "30;41m"); // Black FG, Red BG
            if (exit_info.crashed) {
                print_string("crashed");
            } else {
                print_uint(exit_info.status, 10);
            }

            // End
            print_string(
                reset_colors ++ ansi_esc ++ "31m" ++ // Red FG
                segment_end ++ reset_colors ++ "\n");
        }
    }

    return false;
}

fn lisp_exec(t: *TinyishLisp, command_list: *Expr) TinyishLisp.Error!*Expr {
    var list_iter = command_list;
    var parts_al = std.ArrayList([]const u8).init(alloc);
    defer parts_al.deinit();
    while (try t.next_in_list_iter(&list_iter)) |item| {
        try parts_al.append(t.get_string(item));
    }
    const parts = parts_al.toOwnedSlice();
    defer alloc.free(parts);
    const exit_info = system_calls.exec(&georgios.ProcessInfo{
        .path = parts[0],
        .name = parts[0],
        .args = parts[1..],
    }) catch {
        return t.err;
    };
    return if (exit_info.crashed) t.nil else t.make_int(exit_info.status);
}

fn lisp_run(t: *TinyishLisp, command: *Expr) TinyishLisp.Error!*Expr {
    if (run_command(t.get_string(command))) {
        system_calls.exit(.{});
    }
    return t.nil;
}

fn lisp_exit(t: *TinyishLisp, status_expr: *Expr) TinyishLisp.Error!*Expr {
    const status = status_expr.get_int(u8) orelse return t.err;
    system_calls.exit(.{.status = status});
    return t.nil;
}

fn lisp_add_command(t: *TinyishLisp, name: *Expr, expr: *Expr) TinyishLisp.Error!*Expr {
    custom_commands.put(t.get_string(name), expr) catch return t.err;
    _ = try t.keep_expr(expr);
    return try t.keep_expr(name);
}

const lisp_gen_primitives = [_]TinyishLisp.GenPrimitive{
    .{.name = "exec", .zig_func = lisp_exec, .pass_arg_list = true},
    .{.name = "run", .zig_func = lisp_run},
    .{.name = "exit", .zig_func = lisp_exit},
    .{.name = "add_command", .zig_func = lisp_add_command, .preeval_args = false},
    .{.name = "draw_dragon", .zig_func = draw_dragon},
};
var lisp_primitives: [lisp_gen_primitives.len]TinyishLisp.Primitive = undefined;

fn init_lisp() !void {
    tl = try TinyishLisp.new(alloc);
    tl.out = &generic_console;
    tl.error_out = &generic_console;
    try tl.populate_extra_primitives(lisp_gen_primitives[0..], lisp_primitives[0..]);
    custom_commands = @TypeOf(custom_commands).init(alloc);
}

fn print_lisp_result(expr: *Expr) void {
    if (expr.is_true()) {
        try console.print("{}\n", .{tl.fmt_expr(expr)});
    }
}

fn run_lisp(command: []const u8) void {
    tl.set_input(command, null);
    while (true) {
        const expr_maybe = tl.parse_input() catch |err| {
            try console.print("Interpreter error: {s}\n", .{@errorName(err)});
            break;
        };
        if (expr_maybe) |expr| {
            print_lisp_result(expr);
        } else {
            break;
        }
    }
}

fn run_lisp_file(path: []const u8) !bool {
    var file = try georgios.fs.open(path, .{.ReadOnly = .{}});
    defer file.close() catch unreachable;

    const reader = file.reader();
    tl.parse_all_input(try reader.readAllAlloc(alloc, no_max), path) catch |e| {
        try console.print("shell: error in \"{s}\" error: {s}\n", .{path, @errorName(e)});
        return true;
    };
    return false;
}

pub fn main() !u8 {
    var arena = std.heap.ArenaAllocator.init(georgios.page_allocator);
    alloc = arena.allocator();
    defer arena.deinit();

    generic_console_impl.init(&console);
    generic_console = generic_console_impl.writer();

    try init_lisp();

    if (run_lisp_file("/etc/rc.lisp") catch false) {
        return 1;
    }

    for (georgios.proc_info.args) |arg| {
        if (run_lisp_file(arg) catch |e| {
            try console.print("shell: open \"{s}\" error: {s}\n", .{arg, @errorName(e)});
            return 1;
        }) {
            return 1;
        }
    }

    var got: usize = 0;
    var running = true;
    while (running) {
        // Print Prompt
        print_string(segment_start ++ invert_colors);
        if (system_calls.get_cwd(cwd_buffer[0..])) |dir| {
            if (!(dir.len == 1 and dir[0] == '/')) {
                print_string(dir);
            }
        } else |e| {
            print_string("get_cwd failed: ");
            print_string(@errorName(e));
            print_string("\n");
        }
        print_string("%" ++ invert_colors);

        // Process command
        var getline = true;
        while (getline) {
            const key_event = system_calls.get_key(.Blocking).?;
            if (key_event.char) |c| {
                if (key_event.modifiers.control_is_pressed()) {
                    switch (c) {
                        'd' => {
                            got = 0;
                            running = false;
                            break;
                        },
                        else => {},
                    }
                }
                var print = true;
                if (c == '\n') {
                    getline = false;
                } else if (c == '\x08') {
                    if (got > 0) {
                        got -= 1;
                    } else {
                        print = false;
                    }
                } else if ((got + 1) == command_buffer.len) {
                    print = false;
                } else {
                    command_buffer[got] = c;
                    got += 1;
                }
                if (print) {
                    print_string(@ptrCast([*]const u8, &c)[0..1]);
                }
            }
        }
        if (got > 0) {
            const command = command_buffer[0..got];
            if (command[0] == '(' or command[0] == '\'') {
                run_lisp(command);
            } else if (command[0] == '!') {
                run_lisp(command[1..]);
            } else if (run_command(command)) {
                break; // exit was run
            }

            got = 0;
        }
    }
    print_string("<shell about to exit>\n");

    return 0;
}
