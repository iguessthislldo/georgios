extern var _KERNEL_OFFSET: u32;
pub inline fn offset(address: usize) usize {
    return @ptrToInt(&_KERNEL_OFFSET) + address;
}

pub inline fn out8(port : u16, val: u8) void {
    asm volatile ( "outb %[val], %[port]" : : [val] "{al}" (val), [port] "N{dx}" (port) );
}

// inline out16(u16 port, u16 val) void {
//     asm volatile ( "outw %0, %1" : : "a"(val), "Nd"(port) );
// }

// inline out4(u16 port, u32 val) void {
//     asm volatile ( "outl %0, %1" : : "a"(val), "Nd"(port) );
// }

// inline in8(u16 port) u8 {
//     u1 rv;
//     asm volatile ( "inb %1, %0" : "=a"(rv) : "Nd"(port) );
//     return rv;
// }

// inline in16(u16 port) u16 {
//     u2 rv;
//     asm volatile ( "inw %1, %0" : "=a"(rv) : "Nd"(port) );
//     return rv;
// }

// inline in32(u16 port) u32 {
//     u4 rv;
//     asm volatile ( "inl %1, %0" : "=a"(rv) : "Nd"(port) );
//     return rv;
// }
