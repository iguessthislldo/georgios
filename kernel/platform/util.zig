extern var _KERNEL_OFFSET: u32;
extern var _KERNEL_LOW_END: u32;
extern var _KERNEL_LOW_START: u32;

pub fn kernel_offset(address: u32) u32{
    return @ptrToInt(&_KERNEL_OFFSET) + address;
}

pub fn out8(port: u16, val: u8) void {
    asm volatile ("outb %[val], %[port]" : :
        [val] "{al}" (val), [port] "N{dx}" (port));
}

pub fn out16(port: u16, val: u16) void {
    asm volatile ("outw %[val], %[port]" : :
        [val] "{al}" (val), [port] "N{dx}" (port));
}

pub fn out32(port: u16, val: u32) void {
    asm volatile ("outl %[val], %[port]" : :
        [val] "{al}" (val), [port] "N{dx}" (port));
}

pub fn in8(port: u16) u8 {
    return asm volatile ("inb %[port], %[rv]" :
        [rv] "={al}" (-> u8) : [port] "N{dx}" (port) );
}

pub fn in16(port: u16) u16 {
    return asm volatile ("inw %[port], %[rv]" :
        [rv] "={al}" (-> u16) : [port] "N{dx}" (port) );
}

pub fn in32(port: u16) u32 {
    return asm volatile ("inl %[port], %[rv]" :
        [rv] "={al}" (-> u32) : [port] "N{dx}" (port) );
}

pub fn enable_interrupts() void {
    asm volatile ("sti");
}

pub fn disable_interrupts() void {
    asm volatile ("cli");
}

pub fn halt() noreturn {
    disable_interrupts();
    asm volatile ("hlt");
    unreachable;
}
