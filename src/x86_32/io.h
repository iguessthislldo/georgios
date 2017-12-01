#ifndef X86_IO_HEADER
#define X86_IO_HEADER

#include <stdint.h>

static inline void out8(uint16_t port, uint8_t val) {
    asm volatile ( "outb %0, %1" : : "a"(val), "Nd"(port) );
}

static inline void out16(uint16_t port, uint16_t val) {
    asm volatile ( "outw %0, %1" : : "a"(val), "Nd"(port) );
}

static inline void out32(uint16_t port, uint32_t val) {
    asm volatile ( "outl %0, %1" : : "a"(val), "Nd"(port) );
}

static inline uint8_t in8(uint16_t port) {
    uint8_t rv;
    asm volatile ( "inb %1, %0" : "=a"(rv) : "Nd"(port) );
    return rv;
}

static inline uint16_t in16(uint16_t port) {
    uint16_t rv;
    asm volatile ( "inw %1, %0" : "=a"(rv) : "Nd"(port) );
    return rv;
}

static inline uint32_t in32(uint16_t port) {
    uint32_t rv;
    asm volatile ( "inl %1, %0" : "=a"(rv) : "Nd"(port) );
    return rv;
}

#endif
