const cga_console = @import("cga_console.zig");

const io = @import("../io.zig");

const c = @cImport({
    @cInclude("platform.h");
    @cInclude("memory.h");
});

extern var _KERNEL_OFFSET: u32;
extern var _KERNEL_LOW_END: u32;
extern var _KERNEL_LOW_START: u32;

pub inline fn offset(address: usize) usize {
    return @ptrToInt(&_KERNEL_OFFSET) + address;
}

pub inline fn out8(port: u16, val: u8) void {
    asm volatile ("outb %[val], %[port]" : :
        [val] "{al}" (val), [port] "N{dx}" (port));
}

pub inline fn out16(port: u16, val: u16) void {
    asm volatile ("outw %[val], %[port]" : :
        [val] "{al}" (val), [port] "N{dx}" (port));
}

pub inline fn out32(port: u16, val: u32) void {
    asm volatile ("outl %[val], %[port]" : :
        [val] "{al}" (val), [port] "N{dx}" (port));
}

pub inline fn in8(port: u16) u8 {
    return asm volatile ("inb %[port], %[rv]" :
        [rv] "={al}" (-> u8) : [port] "N{dx}" (port) );
}

pub inline fn in16(port: u16) u16 {
    return asm volatile ("inw %[port], %[rv]" :
        [rv] "={al}" (-> u16) : [port] "N{dx}" (port) );
}

pub inline fn in32(port: u16) u32 {
    return asm volatile ("inl %[port], %[rv]" :
        [rv] "={al}" (-> u32) : [port] "N{dx}" (port) );
}

pub inline fn enable_interrupts() void {
    asm volatile ("sti");
}

pub inline fn disable_interrupts() void {
    asm volatile ("cli");
}

pub fn initialize_io() void {
    // io.console_in = io.new_file() catch |e| null;
    // io.console_out = io.new_file() catch |e| null;
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
