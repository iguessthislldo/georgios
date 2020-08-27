const io = @import("../io.zig");
const print = @import("../print.zig");
const Kernel = @import("../kernel.zig").Kernel;
const kmemory = @import("../memory.zig");

pub const serial_log = @import("serial_log.zig");
pub const cga_console = @import("cga_console.zig");
pub const segments = @import("segments.zig");
pub const interrupts = @import("interrupts.zig");
pub const multiboot = @import("multiboot.zig");
pub const pmemory = @import("memory.zig");
pub const util = @import("util.zig");
pub const pci = @import("pci.zig");

pub const panic = @import("panic.zig").panic;
pub const frame_size = pmemory.frame_size;
pub const Memory = pmemory.Memory;

pub fn done() noreturn {
    asm volatile ("cli");
    while (true) {
        asm volatile ("hlt");
    }
}

extern var _REAL_START: u32;
pub fn kernel_real_start() usize {
    return @ptrToInt(&_REAL_START);
}

extern var _REAL_END: u32;
pub fn kernel_real_end() usize {
    return @ptrToInt(&_REAL_END);
}

extern var _VIRTUAL_START: u32;
pub fn kernel_virtual_start() usize {
    return @ptrToInt(&_VIRTUAL_START);
}

extern var _VIRTUAL_END: u32;
pub fn kernel_virtual_end() usize {
    return @ptrToInt(&_VIRTUAL_END);
}

extern var _KERNEL_SIZE: u32;
pub fn kernel_size() usize {
    return @ptrToInt(&_KERNEL_SIZE);
}

extern var _VIRTUAL_OFFSET: u32;

pub fn kernel_to_real(addr: usize) usize {
    return addr - @ptrToInt(&_VIRTUAL_OFFSET);
}

pub fn kernel_to_virtual(addr: usize) usize {
    return addr + @ptrToInt(&_VIRTUAL_OFFSET);
}

pub fn kernel_range_real_start_available() usize {
    return @intCast(usize, multiboot.kernel_range_start_available);
}

pub fn kernel_range_virtual_start_available() usize {
    return kernel_to_virtual(
        @intCast(usize, multiboot.kernel_range_start_available));
}

fn console_write(file: *io.File, from: []const u8) io.FileError!usize {
    for (from) |value| {
        serial_log.print_char(value);
        cga_console.print_char(value);
    }
    return from.len;
}

extern var stack: [util.Ki(16)]u8 align(16) linksection(".bss");
pub fn print_stack_left() void {
    print.format("stack left: {}\n",
        asm volatile ("mov %%esp, %[x]" : [x] "=r" (-> usize)) - @ptrToInt(&stack));
}

pub fn initialize(kernel: *Kernel) !void {
    // Finish Setup of Console Logging
    serial_log.initialize();
    cga_console.initialize();
    if (kernel.console) |f| {
        f.write_impl = console_write;
    } else {
        @panic("No Console File");
    }

    // Setup Basic CPU Utilities
    segments.initialize();
    interrupts.initialize();
    util.estimate_cpu_speed();

    // List Multiboot Tags
    if (print.debug_print) {
        _ = try multiboot.find_tag(.End);
    }

    // Setup Global Memory Management
    var real_memory_map = kmemory.RealMemoryMap{};
    const mmap_tag = try multiboot.find_tag(.Mmap);
    pmemory.process_multiboot2_mmap(&real_memory_map, &mmap_tag);
    kernel.memory.initialize(&real_memory_map);

    // Setup Devices
    pci.find_pci_devices();
}
