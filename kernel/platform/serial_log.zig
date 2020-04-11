const util = @import("util.zig");
const out8 = util.out8;
const in8 = util.in8;

const com1_port: u16 = 0x3f8;

pub fn initialize() void {
    out8(com1_port + 1, 0x00); // Disable all interrupts
    out8(com1_port + 3, 0x80); // Enable DLAB (set baud rate divisor)
    out8(com1_port + 0, 0x03); // Set divisor to 3 (lo byte) 38400 baud
    out8(com1_port + 1, 0x00); //                  (hi byte)
    out8(com1_port + 3, 0x03); // 8 bits, no parity, one stop bit
    out8(com1_port + 2, 0xC7); // Enable FIFO, clear them, with 14-byte threshold
    out8(com1_port + 4, 0x0B); // IRQs enabled, RTS/DSR set
}

pub fn print_char(c: u8) void {
    while ((in8(com1_port + 5) & 0x20) == 0) {}
    out8(com1_port, c);
}
