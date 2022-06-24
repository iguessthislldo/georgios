const std = @import("std");
const georgios = @import("georgios");
comptime {_ = georgios;}
const system_calls = georgios.system_calls;
const print_string = system_calls.print_string;

const IntType = u32;
const total_size: usize = 1048576;
const total_int_count = total_size / @sizeOf(IntType);

var msg_buffer: [128]u8 = undefined;
var streak_start: usize = 0;
var streak_size: usize = 0;
var total_invalid: usize = 0;

fn streak() !void {
    if (streak_size > 0) {
        var ts = georgios.utils.ToString{.buffer = msg_buffer[0..]};
        try ts.string("At ");
        try ts.uint(streak_start);
        try ts.string(" got ");
        try ts.uint(streak_size);
        try ts.string(" invalid bytes\n");
        print_string(ts.get());
        total_invalid += streak_size;
        streak_size = 0;
        streak_start = 0;
    }
}

pub fn main() void {
    var file = georgios.fs.open("files/test-file") catch |e| {
        print_string("open error: ");
        print_string(@errorName(e));
        print_string("\nNOTE: test-file has to be generated using scripts/gen-test-file.py\n");
        print_string("After that remove disk.img and rebuild\n");
        return;
    };

    var pos: usize = 0;
    var got: usize = 1;
    const buffer_size: usize = 1024;
    var buffer: [buffer_size]u8 = undefined;
    var expected_int: IntType = 0;
    var last_unexpected_int: IntType = 0;
    while (got > 0) {
        if (file.read(buffer[0..])) |g| {
            got = g;
            if (got == 0) break;
            if (got % @sizeOf(IntType) != 0) {
                var ts = georgios.utils.ToString{.buffer = msg_buffer[0..]};
                ts.string("At ") catch unreachable;
                ts.uint(pos) catch unreachable;
                ts.string(" got invalid number of bytes: ") catch unreachable;
                ts.uint(got) catch unreachable;
                ts.char('\n') catch unreachable;
                print_string(ts.get());
                break;
            }

            const ints = std.mem.bytesAsSlice(u32, buffer[0..got]);
            for (ints) |int| {
                if (expected_int != int) {
                    if (int != (last_unexpected_int + 1)) {
                        var ts = georgios.utils.ToString{.buffer = msg_buffer[0..]};
                        ts.string("At ") catch unreachable;
                        ts.uint(pos) catch unreachable;
                        ts.string(" got ") catch unreachable;
                        ts.uint(int) catch unreachable;
                        ts.string(" expected ") catch unreachable;
                        ts.uint(expected_int) catch unreachable;
                        ts.char('\n') catch unreachable;
                        print_string(ts.get());
                    } else {
                        print_string(".");
                    }
                    last_unexpected_int = int;
                    if (streak_size == 0) {
                        streak_start = pos;
                    }
                    streak_size += @sizeOf(IntType);
                } else if (streak_size > 0) {
                    streak() catch |e| {
                        print_string("streak error: ");
                        print_string(@errorName(e));
                        print_string("\n");
                        return;
                    };
                }
                pos += @sizeOf(IntType);
                expected_int += 1;
            }
        } else |e| {
            print_string("file.read error: ");
            print_string(@errorName(e));
            print_string("\n");
            got = 0;
        }
    }
    streak() catch |e| {
        print_string("streak error: ");
        print_string(@errorName(e));
        print_string("\n");
        return;
    };

    {
        var ts = georgios.utils.ToString{.buffer = msg_buffer[0..]};
        ts.uint(total_invalid) catch unreachable;
        ts.string(" out of ") catch unreachable;
        ts.uint(total_size) catch unreachable;
        ts.string(" bytes were invalid\n") catch unreachable;
        print_string(ts.get());
    }

    if (pos != total_size) {
        var ts = georgios.utils.ToString{.buffer = msg_buffer[0..]};
        ts.string("Expected ") catch unreachable;
        ts.uint(total_size) catch unreachable;
        ts.string(" bytes, but got ") catch unreachable;
        ts.uint(pos) catch unreachable;
        ts.string(" bytes\n") catch unreachable;
        print_string(ts.get());
    }

    file.close() catch |e| {
        print_string("file.close error: ");
        print_string(@errorName(e));
        print_string("\n");
        return;
    };
}
