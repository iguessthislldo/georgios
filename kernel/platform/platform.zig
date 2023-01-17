// Platform Initialization and Public Interface

const std = @import("std");
const builtin = @import("builtin");

const kernel = @import("root").kernel;
const io = kernel.io;
const print = kernel.print;

pub const serial_log = @import("serial_log.zig");
pub const cga_console = @import("cga_console.zig");
pub const segments = @import("segments.zig");
pub const interrupts = @import("interrupts.zig");
pub const multiboot = @import("multiboot.zig");
pub const pmemory = @import("memory.zig");
pub const util = @import("util.zig");
pub const pci = @import("pci.zig");
pub const ata = @import("ata.zig");
pub const acpi = @import("acpi.zig");
pub const ps2 = @import("ps2.zig");
pub const threading = @import("threading.zig");
pub const vbe = @import("vbe.zig");
pub const timing = @import("timing.zig");
pub const bios_int = @import("bios_int.zig");

pub const frame_size = pmemory.frame_size;
pub const page_size = pmemory.page_size;
pub const MemoryMgrImpl = pmemory.ManagerImpl;
pub const enable_interrupts = util.enable_interrupts;
pub const disable_interrupts = util.disable_interrupts;
pub const idle = util.idle;
pub const halt_forever = util.halt_forever;

pub const Time = u64;
pub const time = timing.rdtsc;
pub const seconds_to_time = timing.seconds_to_ticks;
pub const milliseconds_to_time = timing.milliseconds_to_ticks;

pub fn panic(msg: []const u8, trace: ?*std.builtin.StackTrace) noreturn {
    _ = msg;
    _ = trace;
    asm volatile ("int $50");
    unreachable;
}

// Kernel Boundaries ==========================================================
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

// Console Implementation =====================================================
fn console_write(file: *io.File, from: []const u8) io.FileError!usize {
    _ = file;
    for (from) |value| {
        serial_log.print_char(value);
        kernel.console.print(value);
    }
    return from.len;
}

fn console_read(file: *io.File, to: []u8) io.FileError!usize {
    _ = file;
    _ = to;
    return 0;
}

// Boot Stack =================================================================
extern var stack: [util.Ki(16)]u8 align(16) linksection(".bss");
pub fn print_stack_left() void {
    print.format("stack left: {}\n",
        asm volatile ("mov %%esp, %[x]" : [x] "=r" (-> usize)) - @ptrToInt(&stack));
}

// Platform Initialization ====================================================
pub fn init() !void {
    // Finish Setup of Console Logging
    serial_log.init();
    cga_console.init();
    kernel.console = &cga_console.console;
    kernel.console_file.write_impl = console_write;
    kernel.console_file.read_impl = console_read;

    // Setup Basic CPU Utilities
    segments.init();
    interrupts.init();
    timing.estimate_cpu_speed();

    // List Multiboot Tags
    if (print.debug_print) {
        _ = try multiboot.find_tag(.End);
    }

    // Setup Global Memory Management
    var real_memory_map = kernel.memory.RealMemoryMap{};
    const mmap_tag = try multiboot.find_tag(.Mmap);
    pmemory.process_multiboot2_mmap(&real_memory_map, &mmap_tag);
    try kernel.memory_mgr.init(&real_memory_map);

    // Threading
    try kernel.threading_mgr.init();

    // Setup Devices
    kernel.device_mgr.init(kernel.alloc.std_allocator());
    try ps2.init();
    pci.find_pci_devices();
    bios_int.init();
    vbe.init();

    try acpi.init();

    // Start Ticking
    timing.set_pit_freq(.Irq0, 100);
    interrupts.pic.allow_irq(0, true);
}

pub fn shutdown() void {
    acpi.power_off();
}
