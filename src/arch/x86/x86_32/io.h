#ifndef X86_IO_HEADER
#define X86_IO_HEADER

#include <library.h>

static inline void out8(u2 port, u1 val) {
    asm volatile ( "outb %0, %1" : : "a"(val), "Nd"(port) );
}

static inline void out16(u2 port, u2 val) {
    asm volatile ( "outw %0, %1" : : "a"(val), "Nd"(port) );
}

static inline void out32(u2 port, u4 val) {
    asm volatile ( "outl %0, %1" : : "a"(val), "Nd"(port) );
}

static inline u1 in8(u2 port) {
    u1 rv;
    asm volatile ( "inb %1, %0" : "=a"(rv) : "Nd"(port) );
    return rv;
}

static inline u2 in16(u2 port) {
    u2 rv;
    asm volatile ( "inw %1, %0" : "=a"(rv) : "Nd"(port) );
    return rv;
}

static inline u4 in32(u2 port) {
    u4 rv;
    asm volatile ( "inl %1, %0" : "=a"(rv) : "Nd"(port) );
    return rv;
}

#endif
