// Miscellaneous Assembly-based Utilities

// x86 I/O Port Access ========================================================

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

/// Copy a series of bytes into destination, like using in8 over the slice.
///
/// https://c9x.me/x86/html/file_module_x86_id_141.html
pub fn in_bytes(port: u16, destination: []u8) void {
    asm volatile ("rep insw" : :
        [port] "{dx}" (port),
        [dest_ptr] "{di}" (@truncate(u32, @ptrToInt(destination.ptr))),
        [dest_size] "{ecx}"  (@truncate(u32, destination.len) >> 1) :
        "memory");
}

// Mask/Unmask Interrupts =====================================================

pub fn enable_interrupts() void {
    asm volatile ("sti");
}

pub fn disable_interrupts() void {
    asm volatile ("cli");
}

// Halt =======================================================================

pub fn halt() void {
    asm volatile ("hlt");
}

pub fn idle() noreturn {
    while (true) {
        enable_interrupts();
        halt();
    }
    unreachable;
}

pub fn done() noreturn {
    disable_interrupts();
    while (true) {
        halt();
    }
    unreachable;
}

// x86 Control Registers ======================================================

/// Page Fault Address
pub fn cr2() u32 {
    return asm volatile ("mov %%cr2, %[rv]" : [rv] "={eax}" (-> u32));
}
