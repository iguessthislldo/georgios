#ifndef X86_32_IRQ
#define X86_32_IRQ

#include <library.h>
#include "io.h"

// IO Ports
#define PIT_CHANNEL 0x40
#define PIT_MODE 0x43
#define PIT_0_7_COMMAND 0x20
#define PIT_0_7_DATA 0x21
#define PIT_8_15_COMMAND 0xA0
#define PIT_8_15_DATA 0xA1

// Commands
#define PIT_RESET 0x20

static inline void pit_reset(u1 irq) {
    if (irq >= 8) out1(PIT_8_15_COMMAND, PIT_RESET);
    out1(PIT_0_7_COMMAND, PIT_RESET);
}

void irq_initialize();

// PIT
extern void ih_irq0();
void irq0_handle();

// PS/2 Keyboard
extern void ih_irq1();
void irq1_handle();

#endif
