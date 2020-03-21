const io = @import("../io.zig");

const cga_console = @import("cga_console.zig");
const segments = @import("segments.zig");
const interrupts = @import("interrupts.zig");
pub const panic = @import("panic.zig").panic;

fn console_out_write(file: *io.File,
        from: [*] const u8, size: usize) io.File.FileError!usize {
    var i: usize = 0;
    while (i < size) {
        cga_console.print_char(from[i]);
        i += 1;
    }
    return size;
}

pub fn initialize_io() void {
    io.console_in = io.new_file() catch |e| null;
    io.console_out = io.new_file() catch |e| null;
    if (io.console_out) |console_out| {
        console_out.write_impl = console_out_write;
    }
}

pub export fn initialize() void {
    cga_console.initialize();
    io.initialize();
    segments.initialize();
    interrupts.initialize();
}
