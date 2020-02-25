const builtin = @import("builtin");

const cga_console = @import("cga_console.zig");

pub inline fn enable_interrupts() void {
    asm volatile ("sti");
}

const c = @cImport({
    @cInclude("platform.h");
    @cInclude("memory.h");
    @cInclude("kernel.h");
    @cInclude("print.h");
});

extern fn serial_out(char: u8) void;
pub export fn x86_32_print_char(ch: u8) void {
    cga_console.print_char(ch);
    serial_out(ch);
}

pub export fn transitional_panic_paint() void {
    const Color = cga_console.Color;
    cga_console.new_page();
    cga_console.set_colors(Color.Black, Color.Red);
    cga_console.fill_screen(' ');
}

pub export fn platform_initialize(mb_info_ptr: usize) void {
    c.kernel_range = 1;
    c.serial_initialize();
    cga_console.initialize();
    c.gdt_initialize();
    c.idt_initialize();
    c.irq_initialize();
    //c.ps2_init();
    c.process_multiboot(mb_info_ptr);
    enable_interrupts();
}

pub fn panic(msg: []const u8, trace: ?*builtin.StackTrace) noreturn {
    c.set_panic_message(&msg[0], msg.len);
    if (trace) |t| {
        c.print_format(c"index: {d}\n", t.index);
        for (t.instruction_addresses) |addr| {
            c.print_format(c" - {x}\n", addr);
        }
    } else {
        c.print_string(c"No Stack Trace\n");
    }
    asm volatile ("pushl $0\n\tint $50");
    unreachable;
}
