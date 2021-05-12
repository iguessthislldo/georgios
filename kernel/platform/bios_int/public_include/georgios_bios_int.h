#ifndef GEORGIOS_BIOS_INT_H
#define GEORGIOS_BIOS_INT_H

#include <stdbool.h>
#include <stdint.h>

typedef struct {
    uint8_t interrupt;
    uint32_t eax;
    uint32_t ebx;
    uint32_t ecx;
    uint32_t edx;
    uint32_t edi;
    bool slow;
} GeorgiosBiosInt;

extern void georgios_bios_int_init(bool trace);
extern bool georgios_bios_int_run(GeorgiosBiosInt * params);
extern void georgios_bios_int_done();

#endif
