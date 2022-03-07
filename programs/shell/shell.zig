const std = @import("std");
const builtin = @import("builtin");

const georgios = @import("georgios");
comptime {_ = georgios;}
const system_calls = georgios.system_calls;
const utils = georgios.utils;

pub fn panic(msg: []const u8, trace: ?*builtin.StackTrace) noreturn {
    georgios.panic(msg, trace);
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
            system_calls.print_string("Failure in middle of check_bin_path?\n");
            return null;
        }
    }
    return null;
}

pub fn main() void {
    system_calls.print_string("Type \"hello\", \"ls\", or \"shell\"\n");
    system_calls.print_string("Type Ctrl-D or \"exit\" to Exit\n");
    var buffer: [128]u8 = undefined;
    var path_buffer: [123]u8 = undefined;
    var cwd_buffer: [128]u8 = undefined;
    var got: usize = 0;
    var running = true;
    while (running) {
        system_calls.print_string("░▒▓\x1b[7m");
        if (system_calls.get_cwd(cwd_buffer[0..])) |dir| {
            if (!(dir.len == 1 and dir[0] == '/')) {
                system_calls.print_string(dir);
            }
        } else |e| {
            system_calls.print_string("???");
        }
        system_calls.print_string("%\x1b[7m");
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
                } else {
                    buffer[got] = c;
                    got += 1;
                }
                if (print) {
                    system_calls.print_string(@ptrCast([*]const u8, &c)[0..1]);
                }
            }
        }
        if (got > 0) {
            var command: []const u8 = buffer[0..got];

            var command_parts: [128][]const u8 = undefined;
            var command_part_count: usize = 0;
            var command_part_len: usize = 0;
            for (command) |c, i| {
                if (c == ' ') {
                    command_parts[command_part_count] = command[i - command_part_len..i];
                    command_part_count += 1;
                    command_part_len = 0;
                } else {
                    command_part_len += 1;
                }
            }
            if (command_part_len > 0) {
                command_parts[command_part_count] = command[command.len - command_part_len..];
                command_part_count += 1;
            }

            if (command_part_count > 0) {
                if (utils.memory_compare(command_parts[0], "exit")) {
                    break;
                } else if (utils.memory_compare(command_parts[0], "reset")) {
                    system_calls.print_string("\x1bc"); // Reset Console
                } else if (utils.memory_compare(command_parts[0], "pwd")) {
                    if (system_calls.get_cwd(cwd_buffer[0..])) |dir| {
                        system_calls.print_string(dir);
                        system_calls.print_string("\n");
                    } else |e| {
                        system_calls.print_string("Couldn't get current working directory: ");
                        system_calls.print_string(@errorName(e));
                        system_calls.print_string("\n");
                    }
                } else if (utils.memory_compare(command_parts[0], "cd")) {
                    if (command_part_count != 2) {
                        system_calls.print_string("cd requires exactly one argument\n");
                    } else {
                        system_calls.set_cwd(command_parts[1]) catch |e| {
                            system_calls.print_string("Couldn't change current working directory to \"");
                            system_calls.print_string(command_parts[1]);
                            system_calls.print_string("\": ");
                            system_calls.print_string(@errorName(e));
                            system_calls.print_string("\n");
                        };
                    }
                } else if (utils.memory_compare(command_parts[0], "sleep")) {
                    if (command_part_count != 2) {
                        system_calls.print_string("sleep requires exactly one argument\n");
                    } else {
                        if (std.fmt.parseUnsigned(usize, command_parts[1], 10)) |n| {
                            system_calls.sleep_seconds(n);
                        } else |e| {
                            system_calls.print_string("invalid argument\n");
                        }
                    }
                } else if (utils.memory_compare(command_parts[0], "koverflow")) {
                    system_calls.overflow_kernel_stack();
                } else {
                    var command_path = command_parts[0];
                    if (check_bin_path("bin", command_parts[0], path_buffer[0..])) |path| {
                        command_path = path[0..];
                    }
                    system_calls.exec(&georgios.ProcessInfo{
                        .path = command_path,
                        .name = command_parts[0],
                        .args = command_parts[1..command_part_count],
                    }) catch |e| {
                        system_calls.print_string("Command: \"");
                        system_calls.print_string(command);
                        system_calls.print_string("\" failed: ");
                        system_calls.print_string(@errorName(e));
                        system_calls.print_string("\n");
                    };
                }
            }
            got = 0;
        }
    }
    system_calls.print_string("<shell about to exit>\n");
    system_calls.exit(0);
}
