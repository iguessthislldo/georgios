const io = @import("../io.zig");
const print = @import("../print.zig");
const Kernel = @import("../kernel.zig").Kernel;
const kutil = @import("../util.zig");

pub const frame_size = kutil.KiB(4);
pub const panic = @import("panic.zig").panic;

const serial_log = @import("serial_log.zig");
const cga_console = @import("cga_console.zig");
const segments = @import("segments.zig");
const interrupts = @import("interrupts.zig");
const multiboot = @import("multiboot.zig");

extern var _KERNEL_OFFSET: u32;
pub fn kernel_offset(address: u32) u32{
    return @ptrToInt(&_KERNEL_OFFSET) + address;
}

extern var _KERNEL_LOW_START: u32;
pub fn kernel_real_start() usize {
    return @ptrToInt(&_KERNEL_LOW_START);
}

extern var _KERNEL_LOW_END: u32;
pub fn kernel_real_end() usize {
    return @ptrToInt(&_KERNEL_LOW_END);
}

extern var _KERNEL_HIGH_START: u32;
pub fn kernel_virtual_start() usize {
    return @ptrToInt(&_KERNEL_HIGH_START);
}

extern var _KERNEL_HIGH_END: u32;
pub fn kernel_virtual_end() usize {
    return @ptrToInt(&_KERNEL_HIGH_END);
}

extern var _KERNEL_SIZE: u32;
pub fn kernel_size() usize {
    return @ptrToInt(&_KERNEL_SIZE);
}

fn console_write(file: *io.File,
        from: [*] const u8, size: usize) io.FileError!usize {
    var i: usize = 0;
    while (i < size) {
        serial_log.print_char(from[i]);
        cga_console.print_char(from[i]);
        i += 1;
    }
    return size;
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
}
