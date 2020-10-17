const std = @import("std");

const io = @import("io.zig");
const fprint = @import("fprint.zig");

pub const Log = struct {
    const Self = @This();
    const tab = "  ";
    const marker = " - ";

    file: ?*io.File,
    indent: usize = 0,
    parent: ?*const Self = null,
    enabled: bool = true,

    pub fn child(self: *const Self) Self {
        return Self{.indent = self.indent + 1, .file = self.file, .parent = self};
    }

    fn is_enabled(self: *const Self) bool {
        var logger: ?*const Self = self;
        while (logger) |l| {
            if (!l.enabled) {
                return false;
            }
            logger = l.parent;
        }
        return true;
    }

    fn print_indent(file: *io.File, indent: usize) void {
        var i: usize = 0;
        while (i < indent) {
            _ = fprint.string(file, tab) catch {};
            i += 1;
        }
        _ = fprint.string(file, marker) catch {};
    }

    pub fn log(self: *const Self, comptime fmtstr: []const u8, args: ...) void {
        if (self.file) |file| {
            if (self.is_enabled()) {
                print_indent(file, self.indent);
                _ = fprint.format(file, fmtstr ++ "\n", args) catch {};
            }
        }
    }
};

test "Log" {
    var buffer: [1024]u8 = undefined;
    var buffer_file = io.BufferFile{};
    buffer_file.initialize(buffer[0..]);
    const file = &buffer_file.file;

    {
        buffer_file.reset();
        var log = Log{.file = file};
        log.log("{}, World!", "Hello");
        buffer_file.expect(" - Hello, World!\n");
    }

    {
        buffer_file.reset();
        var log1 = Log{.file = file};
        log1.log("1");
        log1.enabled = false;
        log1.log("SHOULD NOT BE LOGGED");
        log1.enabled = true;
        log1.log("2");
        {
            var log2 = log1.child();
            log2.log("3");
            {
                var log3 = log2.child();
                log3.log("4");
                log1.enabled = false;
                log3.log("SHOULD NOT BE LOGGED");
                log1.enabled = true;
                log3.log("5");
            }
            log2.log("6");
            log2.log("7");
        }
        log1.log("8");
        buffer_file.expect(
            \\ - 1
            \\ - 2
            \\   - 3
            \\     - 4
            \\     - 5
            \\   - 6
            \\   - 7
            \\ - 8
            \\
            );
    }
}
