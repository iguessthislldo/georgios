#ifndef GEROGIOS_BIOS_INT_SYS_IO_H
#define GEROGIOS_BIOS_INT_SYS_IO_H

#include <stdint.h>

#define inb georgios_bios_int_inb
extern uint8_t inb(uint16_t port);
#define inw georgios_bios_int_inw
extern uint16_t inw(uint16_t port);
#define inl georgios_bios_int_inl
extern uint32_t inl(uint16_t port);
#define outb georgios_bios_int_outb
extern uint8_t outb(uint16_t port, uint8_t value);
#define outw georgios_bios_int_outw
extern uint16_t outw(uint16_t port, uint16_t value);
#define outl georgios_bios_int_outl
extern uint32_t outl(uint16_t port, uint16_t value);

#endif
