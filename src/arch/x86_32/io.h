#ifndef X86_IO_HEADER
#define X86_IO_HEADER

#include <library.h>

static inline void out8(u16 port, u8 val) {
    asm volatile ( "outb %0, %1" : : "a"(val), "Nd"(port) );
}

static inline void out16(u16 port, u16 val) {
    asm volatile ( "outw %0, %1" : : "a"(val), "Nd"(port) );
}

static inline void out32(u16 port, u32 val) {
    asm volatile ( "outl %0, %1" : : "a"(val), "Nd"(port) );
}

static inline u8 in8(u16 port) {
    u8 rv;
    asm volatile ( "inb %1, %0" : "=a"(rv) : "Nd"(port) );
    return rv;
}

static inline u16 in16(u16 port) {
    u16 rv;
    asm volatile ( "inw %1, %0" : "=a"(rv) : "Nd"(port) );
    return rv;
}

static inline u32 in32(u16 port) {
    u32 rv;
    asm volatile ( "inl %1, %0" : "=a"(rv) : "Nd"(port) );
    return rv;
}

#endif
