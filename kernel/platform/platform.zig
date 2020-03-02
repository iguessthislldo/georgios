const io = @import("../io.zig");

const cga_console = @import("cga_console.zig");
const segments = @import("segments.zig");

pub export fn transitional_panic_paint() void {
    const Color = cga_console.Color;
    cga_console.new_page();
    cga_console.set_colors(Color.Black, Color.Red);
    cga_console.fill_screen(' ');
}

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
    segments.kernel_code_selector = 0;
}
