const std = @import("std");

const georgios = @import("georgios");
comptime {_ = georgios;}
const system_calls = georgios.system_calls;
const utils = georgios.utils;

const print_string = system_calls.print_string;

pub fn panic(msg: []const u8, trace: ?*std.builtin.StackTrace) noreturn {
    georgios.panic(msg, trace);
}

var img_buffer: [2048]u8 align(@alignOf(u64)) = undefined;

fn read_motd() void {
    if (system_calls.vbe_res()) |res| {
        var img = georgios.fs.open("/files/dragon.img") catch |e| {
            print_string("shell: open img error: ");
            print_string(@errorName(e));
            print_string("\n");
            return;
        };

        const img_width: u32 = 301;
        // const img_height: u32 = 170;
        const pos = utils.Point{.x = res.x - img_width - 10, .y = 10};
        var last = utils.Point{};
        var got: usize = 1;
        while (got > 0) {
            if (img.read(img_buffer[0..])) |g| {
                got = g;
            } else |e| {
                print_string("shell: img file.read error: ");
                print_string(@errorName(e));
                print_string("\n");
                got = 0;
            }
            if (got > 0) {
                system_calls.vbe_draw_raw_image_chunk(img_buffer[0..got], img_width, pos, last);
            }
        }
        system_calls.vbe_flush_buffer();

        img.close() catch |e| {
            print_string("shell: img file.close error: ");
            print_string(@errorName(e));
            print_string("\n");
            return;
        };
    }

    var file = georgios.fs.open("/etc/motd") catch |e| {
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
    var dir_entry = georgios.DirEntry{.dir = path};
    if (system_calls.next_dir_entry(&dir_entry)) {
        return null;
    }
    var pos = utils.memory_copy_truncate(buffer[0..], name);
    pos = pos + utils.memory_copy_truncate(buffer[pos..], ".elf");
    while (!dir_entry.done) {
        if (utils.memory_compare(dir_entry.current_entry, buffer[0..pos])) {
            pos = 0;
            pos = utils.memory_copy_truncate(buffer, path);
            pos = pos + utils.memory_copy_truncate(buffer[pos..], "/");
            pos = pos + utils.memory_copy_truncate(buffer[pos..], dir_entry.current_entry);
            return buffer[0..pos];
        }
        if (system_calls.next_dir_entry(&dir_entry)) {
            print_string("Failure in middle of check_bin_path?\n");
            return null;
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
    if (utils.memory_compare(command_parts[0], "exit")) {
        return true;
    } else if (utils.memory_compare(command_parts[0], "reset")) {
        print_string("\x1bc"); // Reset Console
    } else if (utils.memory_compare(command_parts[0], "pwd")) {
        if (system_calls.get_cwd(cwd_buffer[0..])) |dir| {
            print_string(dir);
            print_string("\n");
        } else |e| {
            print_string("Couldn't get current working directory: ");
            print_string(@errorName(e));
            print_string("\n");
        }
    } else if (utils.memory_compare(command_parts[0], "cd")) {
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
    } else if (utils.memory_compare(command_parts[0], "sleep")) {
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
    } else if (utils.memory_compare(command_parts[0], "koverflow")) {
        system_calls.overflow_kernel_stack();
    } else if (utils.memory_compare(command_parts[0], "motd")) {
        read_motd();
    } else {
        var command_path = command_parts[0];
        var path_buffer: [128]u8 = undefined;
        if (check_bin_path("/bin", command_parts[0], path_buffer[0..])) |path| {
            command_path = path[0..];
        }
        system_calls.exec(&georgios.ProcessInfo{
            .path = command_path,
            .name = command_parts[0],
            .args = command_parts[1..command_part_count],
        }) catch |e| {
            print_string("Command: \"");
            print_string(command);
            print_string("\" failed: ");
            print_string(@errorName(e));
            print_string("\n");
        };
    }

    return false;
}

pub fn main() void {
    if (system_calls.get_process_id() == 0) {
        read_motd();
    }
    var got: usize = 0;
    var running = true;
    while (running) {
        print_string("░▒▓\x1b[7m");
        if (system_calls.get_cwd(cwd_buffer[0..])) |dir| {
            if (!(dir.len == 1 and dir[0] == '/')) {
                system_calls.print_string(dir);
            }
        } else |e| {
            print_string("get_cwd failed: ");
            print_string(@errorName(e));
            print_string("\n");
        }
        print_string("%\x1b[7m");
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
            if (run_command(command_buffer[0..got])) {
                break; // exit was run
            }

            got = 0;
        }
    }
    print_string("<shell about to exit>\n");
    system_calls.exit(0);
}
