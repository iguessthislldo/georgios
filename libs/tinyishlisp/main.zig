const std = @import("std");

const utils = @import("utils");
const TinyishLisp = @import("TinyishLisp.zig");

const no_max = std.math.maxInt(usize);

const OurToString = struct {
    writer: *std.fs.File.Writer,
    ts: utils.ToString = .{.ext_func = ts_print_str},

    fn ts_print_str(ts: *utils.ToString, s: []const u8) void {
        const self = @fieldParentPtr(OurToString, "ts", ts);
        _ = self.writer.write(s) catch |e| {
            @panic(@errorName(e));
        };
    }
};

pub fn main() !u8 {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const stdin = std.io.getStdIn().reader();
    var stdout = std.io.getStdOut().writer();
    var stderr = std.io.getStdErr().writer();

    var stdout_ots = OurToString{.writer = &stdout};
    var stderr_ots = OurToString{.writer = &stderr};
    var tl = try TinyishLisp.new(allocator);

    var line_contents = std.ArrayList(u8).init(allocator);
    defer line_contents.deinit();

    var argit = std.process.args();
    _ = argit.skip();
    while (argit.next(allocator)) |_arg| {
        const arg = _arg catch unreachable;
        try stdout.print("{s}\n", .{arg});
        const lisp_file = try std.fs.cwd().openFile(arg, .{.read = true});
        defer lisp_file.close();
        const reader = lisp_file.reader();
        try tl.parse_all_input(try reader.readAllAlloc(allocator, no_max), arg, &stderr_ots.ts);
    }

    while (true) {
        try stdout.print("> ", .{});
        stdin.readUntilDelimiterArrayList(&line_contents, '\n', no_max) catch |e| {
            if (e == error.EndOfStream) {
                break;
            } else {
                return e;
            }
        };
        tl.set_input(line_contents.toOwnedSlice(), null, &stderr_ots.ts);
        while (true) {
            const expr_maybe = tl.parse_input() catch |err| {
                try stderr.print("Interpreter error: {s}\n", .{@errorName(err)});
                continue;
            };
            if (expr_maybe) |expr| {
                try tl.print_expr(&stdout_ots.ts, expr);
                _ = try stdout.write("\n");
            } else {
                break;
            }
        }
    }

    return 0;
}
