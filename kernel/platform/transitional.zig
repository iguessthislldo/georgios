const cga_console = @import("cga_console.zig");

export fn transitional_initialize_cga_console() void {
    cga_console.initialize();
}

extern fn serial_out(c: u8) void;
export fn transitional_print_char(c: u8) void {
    cga_console.print_char(c);
    serial_out(c);
}

export fn transitional_panic_paint() void {
    cga_console.new_page();
    cga_console.set_colors(cga_console.Color.Black, cga_console.Color.Red);
    cga_console.fill_screen(' ');
}
