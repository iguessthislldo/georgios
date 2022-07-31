const std = @import("std");

const georgios = @import("georgios");
comptime {_ = georgios;}
const syscalls = georgios.system_calls;
const utils = georgios.utils;
const streq = utils.memory_compare;

const console = georgios.get_console_writer();
const no_max = std.math.maxInt(usize);

pub fn panic(msg: []const u8, trace: ?*std.builtin.StackTrace) noreturn {
    georgios.panic(msg, trace);
}

var alloc: std.mem.Allocator = undefined;
var input_buffer: [256]u8 = undefined;
var running = true;

var current_line: usize = 1;
var path: ?[]u8 = null;
var buffer: utils.List([]u8) = undefined;

fn get_line(num: usize) ?[]u8 {
    if (num == 0) return null;
    var it = buffer.iterator();
    var current: usize = 1;
    while (it.next()) |line| {
        if (num == current) return line;
        current += 1;
    }
    return null;
}

fn write_file() !void {
    if (path == null) {
        try console.print("No path set\n", .{});
    }
    var file = try georgios.fs.open(path.?, .{.Write = .{.truncate = true}});
    defer file.close() catch unreachable;

    _ = try file.seek(0, .FromStart);
    var it = buffer.iterator();
    while (it.next()) |line| {
        _ = try file.write_or_error(line);
        _ = try file.write_or_error("\n");
    }
}

fn read_file() !void {
    if (path == null) {
        try console.print("No path set\n", .{});
    }
    var file = try georgios.fs.open(path.?, .{.ReadOnly = .{}});
    defer file.close() catch unreachable;

    var reader = file.reader();
    current_line = 0;
    while (try reader.readUntilDelimiterOrEofAlloc(alloc, '\n', no_max)) |line| {
        try buffer.push_back(line);
        current_line += 1;
    }
    if (current_line == 0) {
        current_line = 1;
    }
}

fn get_input(prompt: bool) ?[]const u8 {
    if (prompt) {
        try console.print(":", .{});
    }

    var got: usize = 0;
    while (true) {
        const key_event = syscalls.get_key(.Blocking).?;
        if (key_event.char) |c| {
            if (key_event.modifiers.control_is_pressed()) {
                switch (c) {
                    'd' => return null,
                    else => {},
                }
            }
            var print = true;
            if (c == '\n') {
                try console.print("\n", .{});
                break;
            } else if (c == '\x08') {
                if (got > 0) {
                    got -= 1;
                } else {
                    print = false;
                }
            } else if ((got + 1) == input_buffer.len) {
                print = false;
            } else {
                input_buffer[got] = c;
                got += 1;
            }
            if (print) {
                try console.print("{c}", .{c});
            }
        }
    }
    return input_buffer[0..got];
}

pub fn main() !u8 {
    if (georgios.proc_info.args.len != 1) {
        return 1;
    }

    var arena = std.heap.ArenaAllocator.init(georgios.page_allocator);
    alloc = arena.allocator();
    defer arena.deinit();

    path = try alloc.dupe(u8, georgios.proc_info.args[0]);
    buffer = .{.alloc = alloc};
    read_file() catch |e| {
        try console.print("Could not open {s}: {s}\n", .{path, @errorName(e)});
    };

    var append = false;
    while (get_input(!append)) |input| {
        if (append) {
            try buffer.push_back(try alloc.dupe(u8, input));
            append = false;
        } else {
            if (streq(input, "a")) {
                append = true;
                continue;
            } else if (streq(input, "q")) {
                break;
            } else if (streq(input, "w")) {
                try write_file();
                continue;
            } else if (streq(input, ",")) {
                if (get_line(current_line)) |line| {
                    try console.print("{s}\n", .{line});
                } else {
                    current_line = 1;
                }
                continue;
            } else if (streq(input, ",p")) {
                var it = buffer.iterator();
                while (it.next()) |line| {
                    try console.print("{s}\n", .{line});
                }
                continue;
            }
            const line_no = std.fmt.parseUnsigned(usize, input, 10) catch {
                try console.print("Invalid command: {s}\n", .{input});
                continue;
            };
            if (get_line(line_no)) |line| {
                current_line = line_no;
                try console.print("{s}\n", .{line});
            } else {
                try console.print("Invalid line: {s}\n", .{input});
            }
        }
    }

    return 0;
}
