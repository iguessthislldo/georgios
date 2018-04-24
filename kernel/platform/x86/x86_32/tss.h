#ifndef TSS_HEADER
#define TSS_HEADER

#include <library.h>

typedef struct {
    u2 link, zero1;
    u4 esp0;
    u2 ss0, zero2;
    u4 esp1;
    u2 ss1, zero3;
    u4 esp3;
    u2 ss2, zero4;
    u4 cr3, eip, eflags, eax, ecx, edx, ebx, esp, ebp, esi, edi;
    u2 es, zero5, cs, zero6, ss, zero7, ds, zero8, fs, zero9, gs, zero10;
    u2 ldt_selector, zero11, trap, io_map;
} tss __attribute__((packed));

typedef struct { // 64 bits total
    u2 segment_limit; // 16 bits
    u2 base_0_15; // 16 bits
    u1 base_16_23; // 8 bits
    u1 fixed1 : 1; // = 1, 1 bit
    bool busy : 1; // 1 bit
    u1 fixed2 : 3; // = 2, 3 bits
    u1 privilege_level : 2; // 2 bits
    bool present : 1; // 1 bit
    u1 limit : 4; // 4 bits
    bool avaliable : 1; // 1 bit
    u1 fixed3 : 2; // = 0, 2 bits
    bool granularity : 1; // 1 bit
    u1 base_24_31; // 8 bits
} tts_discriptor __attribute__((packed));

#endif
