const std = @import("std");

const georgios = @import("georgios");
comptime {_ = georgios;}
const system_calls = georgios.system_calls;
const utils = georgios.utils;
const streq = utils.memory_compare;
const TinyishLisp = @import("TinyishLisp");

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

var alloc: std.mem.Allocator = undefined;

var img_buffer: [2048]u8 align(@alignOf(u64)) = undefined;

var tl: TinyishLisp = undefined;

const console_writer = georgios.get_console_writer();

const OurToString = struct {
    ts: utils.ToString = .{.ext_func = ts_print_str},

    fn ts_print_str(ts: *utils.ToString, s: []const u8) void {
        const self = @fieldParentPtr(OurToString, "ts", ts);
        _ = self;
        print_string(s);
    }
};

fn draw_dragon() void {
    if (system_calls.vbe_res()) |res| {
        var file = georgios.fs.open("/files/dragon.img", .{.ReadOnly = .{}}) catch |e| {
            print_string("shell: open file error: ");
            print_string(@errorName(e));
            print_string("\n");
            return;
        };
        var img = georgios.ImgFile{.file = &file, .buffer = img_buffer[0..]};
        img.parse_header() catch |e| {
            print_string("shell: invalid image file: ");
            print_string(@errorName(e));
            print_string("\n");
            return;
        };

        img.draw(.{.x = res.x - img.size.?.x - 10, .y = 10}) catch |e| {
            print_string("shell: draw: ");
            print_string(@errorName(e));
            print_string("\n");
            return;
        };
        system_calls.vbe_flush_buffer();

        file.close() catch |e| {
            print_string("shell: img file.close error: ");
            print_string(@errorName(e));
            print_string("\n");
            return;
        };
    }
}

fn read_motd() void {
    draw_dragon();

    var file = georgios.fs.open("/etc/motd", .{.ReadOnly = .{}}) catch |e| {
        print_string("motd open error: ");
        print_string(@errorName(e));
        print_string("\n");
        return;
    };

    var buffer: [128]u8 = undefined;
    var got: usize = 1;
    while (got > 0) {
        if (file.read(buffer[0..])) |g| {
            got = g;
        } else |e| {
            print_string("motd file.read error: ");
            print_string(@errorName(e));
            print_string("\n");
            got = 0;
        }
        if (got > 0) {
            print_string(buffer[0..got]);
        }
    }

    file.close() catch |e| {
        print_string("motd file.close error: ");
        print_string(@errorName(e));
        print_string("\n");
    };
}

fn check_bin_path(path: []const u8, name: []const u8, buffer: []u8) ?[]const u8 {
    var dir_file = georgios.fs.open(path, .{.ReadOnly = .{.dir = true}}) catch |e| {
        print_string("check_bin_path open error: ");
        print_string(@errorName(e));
        print_string("\n");
        return null;
    };
    defer dir_file.close() catch unreachable;
    var pos = utils.memory_copy_truncate(buffer[0..], name);
    pos = pos + utils.memory_copy_truncate(buffer[pos..], ".elf");
    var entry_buffer: [256]u8 = undefined;
    while (true) {
        const read = dir_file.read(entry_buffer[0..]) catch |e| {
            print_string("check_bin_path read error: ");
            print_string(@errorName(e));
            print_string("\n");
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
        print_string(reset_console);
    } else if (streq(command_parts[0], "pwd")) {
        if (system_calls.get_cwd(cwd_buffer[0..])) |dir| {
            print_string(dir);
            print_string("\n");
        } else |e| {
            print_string("Couldn't get current working directory: ");
            print_string(@errorName(e));
            print_string("\n");
        }
    } else if (streq(command_parts[0], "cd")) {
        if (command_part_count != 2) {
            print_string("cd requires exactly one argument\n");
        } else {
            system_calls.set_cwd(command_parts[1]) catch |e| {
                print_string("Couldn't change current working directory to \"");
                print_string(command_parts[1]);
                print_string("\": ");
                print_string(@errorName(e));
                print_string("\n");
            };
        }
    } else if (streq(command_parts[0], "sleep")) {
        if (command_part_count != 2) {
            print_string("sleep requires exactly one argument\n");
        } else {
            if (std.fmt.parseUnsigned(usize, command_parts[1], 10)) |n| {
                system_calls.sleep_seconds(n);
            } else |e| {
                print_string("invalid argument: ");
                print_string(@errorName(e));
                print_string("\n");
            }
        }
    } else if (streq(command_parts[0], "motd")) {
        read_motd();
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
            print_string("Command: \"");
            print_string(command);
            print_string("\" failed: ");
            print_string(@errorName(e));
            print_string("\n");
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

fn run_lisp(command: []const u8) void {
    var ots = OurToString{};
    tl.set_input(command, null, &ots.ts);
    while (true) {
        const expr_maybe = tl.parse_input() catch |err| {
            print_string("Interpreter error: ");
            print_string(@errorName(err));
            print_string("\n");
            break;
        };
        if (expr_maybe) |expr| {
            tl.print_expr(&ots.ts, expr) catch |err| {
                print_string("Could not print expression error: ");
                print_string(@errorName(err));
                print_string("\n");
                break;
            };
            print_string("\n");
        } else {
            break;
        }
    }
}

pub fn main() void {
    if (system_calls.get_process_id() == 0) {
        read_motd();
    }

    var arena = std.heap.ArenaAllocator.init(georgios.page_allocator);
    alloc = arena.allocator();
    defer arena.deinit();

    tl = TinyishLisp.new(alloc) catch |e| {
        print_string("lisp init failed: ");
        print_string(@errorName(e));
        print_string("\n");
        return;
    };

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
}
