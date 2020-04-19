const io = @import("../io.zig");
const print = @import("../print.zig");
const Kernel = @import("../kernel.zig").Kernel;

const serial_log = @import("serial_log.zig");
const cga_console = @import("cga_console.zig");
const segments = @import("segments.zig");
const interrupts = @import("interrupts.zig");
const multiboot = @import("multiboot.zig");
const paging = @import("paging.zig");
const putil = @import("util.zig");

pub const panic = @import("panic.zig").panic;

pub fn done() noreturn {
    asm volatile ("cli");
    while (true) {
        asm volatile ("hlt");
    }
}

extern var _KERNEL_OFFSET: u32;
pub fn kernel_offset(address: u32) u32{
    return @ptrToInt(&_KERNEL_OFFSET) + address;
}

extern var _KERNEL_REAL_START: u32;
pub fn kernel_real_start() usize {
    return @ptrToInt(&_KERNEL_REAL_START);
}

extern var _KERNEL_REAL_END: u32;
pub fn kernel_real_end() usize {
    return @ptrToInt(&_KERNEL_REAL_END);
}

extern var _KERNEL_VIRTUAL_START: u32;
pub fn kernel_virtual_start() usize {
    return @ptrToInt(&_KERNEL_VIRTUAL_START);
}

extern var _KERNEL_VIRTUAL_END: u32;
pub fn kernel_virtual_end() usize {
    return @ptrToInt(&_KERNEL_VIRTUAL_END);
}

extern var _KERNEL_SIZE: u32;
pub fn kernel_size() usize {
    return @ptrToInt(&_KERNEL_SIZE);
}

pub const frame_size = paging.frame_size;

fn console_write(file: *io.File, from: []const u8) io.FileError!usize {
    for (from) |value| {
        serial_log.print_char(value);
        cga_console.print_char(value);
    }
    return from.len;
}

pub fn initialize(kernel: *Kernel) !void {
    serial_log.initialize();
    cga_console.initialize();
    if (kernel.console) |f| {
        f.write_impl = console_write;
    }
    segments.initialize();
    interrupts.initialize();
    try multiboot.process_tag(kernel, .End); // List Multiboot Tags

    // Setup Memory
    try multiboot.process_tag(kernel, .Mmap);
    // TODO: defer freeing memory containing multiboot structure
//     paging.enable_paging();
}
