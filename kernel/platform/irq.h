#ifndef X86_32_IRQ
#define X86_32_IRQ

#include <library.h>
#include "io.h"

// IO Ports
#define PIC_CHANNEL 0x40
#define PIC_MODE 0x43
#define PIC_0_7_COMMAND 0x20
#define PIC_0_7_DATA 0x21
#define PIC_8_15_COMMAND 0xA0
#define PIC_8_15_DATA 0xA1

// Commands
#define PIC_RESET 0x20

static inline void pic_reset(u1 irq) {
    if (irq >= 8) out1(PIC_8_15_COMMAND, PIC_RESET);
    out1(PIC_0_7_COMMAND, PIC_RESET);
}

void irq_initialize();

// PIT
extern void ih_irq0();
void irq0_handle();

// PS/2 Keyboard
extern void ih_irq1();
void irq1_handle();

#endif
