#ifndef X86_IO_HEADER
#define X86_IO_HEADER

#include <basic_types.h>

static inline void out1(u2 port, u1 val) {
    asm volatile ( "outb %0, %1" : : "a"(val), "Nd"(port) );
}

static inline void out2(u2 port, u2 val) {
    asm volatile ( "outw %0, %1" : : "a"(val), "Nd"(port) );
}

static inline void out4(u2 port, u4 val) {
    asm volatile ( "outl %0, %1" : : "a"(val), "Nd"(port) );
}

static inline u1 in1(u2 port) {
    u1 rv;
    asm volatile ( "inb %1, %0" : "=a"(rv) : "Nd"(port) );
    return rv;
}

static inline u2 in2(u2 port) {
    u2 rv;
    asm volatile ( "inw %1, %0" : "=a"(rv) : "Nd"(port) );
    return rv;
}

static inline u4 in4(u2 port) {
    u4 rv;
    asm volatile ( "inl %1, %0" : "=a"(rv) : "Nd"(port) );
    return rv;
}

static inline void insl(u2 port, void *dest, u4 size) {
    asm volatile ("cld; rep insl" :
        "=D" (dest), "=c" (size) :
        "d" (port), "0" (dest), "1" (size) :
        "memory", "cc");
}

static inline void insw(u2 port, void *dest, u4 size) {
    asm volatile ("rep insw" :
        "+D" (dest), "+c" (size) :
        "d" (port) : "memory");
}

#endif
