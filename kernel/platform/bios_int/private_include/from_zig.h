#ifndef GEORGIOS_BIOS_INT_FROM_ZIG_H
#define GEORGIOS_BIOS_INT_FROM_ZIG_H

#include <stdint.h>

extern void georgios_bios_int_print_string(const char * str);
extern void georgios_bios_int_print_value(uint32_t value);
extern void georgios_bios_int_wait();

extern uint8_t georgios_bios_int_rdb(uint32_t addr);
extern uint16_t georgios_bios_int_rdw(uint32_t addr);
extern uint32_t georgios_bios_int_rdl(uint32_t addr);
extern void georgios_bios_int_wrb(uint32_t addr, uint8_t value);
extern void georgios_bios_int_wrw(uint32_t addr, uint16_t value);
extern void georgios_bios_int_wrl(uint32_t addr, uint32_t value);

// Port I/O is in sys/io.h

#endif
