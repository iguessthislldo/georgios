const std = @import("std");

const utils = @import("utils");
const TinyishLisp = @import("TinyishLisp.zig");

const no_max = std.math.maxInt(usize);

pub fn main() !u8 {
    var gpa: std.heap.GeneralPurposeAllocator(.{.stack_trace_frames = 32}) = .{};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const stdin = std.io.getStdIn().reader();
    var stdout = std.io.getStdOut().writer();
    var stderr = std.io.getStdErr().writer();

    var tl = try TinyishLisp.new(allocator);
    defer tl.done();

    var generic_stdout_impl = utils.GenericWriterImpl(@TypeOf(stdout)){};
    generic_stdout_impl.init(&stdout);
    var generic_stdout = generic_stdout_impl.writer();
    tl.out = &generic_stdout;

    var generic_stderr_impl = utils.GenericWriterImpl(@TypeOf(stderr)){};
    generic_stderr_impl.init(&stderr);
    var generic_stderr = generic_stderr_impl.writer();
    tl.error_out = &generic_stderr;

    var argit = std.process.args();
    _ = argit.skip();
    while (argit.next(allocator)) |_arg| {
        const arg = _arg catch unreachable;
        try stdout.print("{s}\n", .{arg});
        const lisp_file = try std.fs.cwd().openFile(arg, .{.read = true});
        defer lisp_file.close();
        const reader = lisp_file.reader();
        try tl.parse_all_input(try reader.readAllAlloc(allocator, no_max), arg);
    }

    var line_contents = std.ArrayList(u8).init(allocator);
    defer line_contents.deinit();
    while (true) {
        try stdout.print("> ", .{});
        stdin.readUntilDelimiterArrayList(&line_contents, '\n', no_max) catch |e| {
            if (e == error.EndOfStream) {
                break;
            } else {
                return e;
            }
        };
        const line = line_contents.toOwnedSlice();
        defer allocator.free(line);
        tl.set_input(line, null);
        while (true) {
            const expr_maybe = tl.parse_input() catch |err| {
                try stderr.print("Interpreter error: {s}\n", .{@errorName(err)});
                continue;
            };
            if (expr_maybe) |expr| {
                if (expr.is_true()) {
                    try stdout.print("{repr}\n", tl.fmt_expr(expr));
                }
            } else {
                break;
            }
        }
    }

    return 0;
}
