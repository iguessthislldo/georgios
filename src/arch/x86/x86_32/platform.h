#ifndef X86_32_PLATFORM_HEADER
#define X86_32_PLATFORM_HEADER

#if defined(__GNUC__) && defined(__i386__)
#define x86_32
#endif

#ifdef x86_32
#define PLATFORM_SUPPORTED

#include <library.h>

#include "fb.h"
#include "gdt.h"
#include "idt.h"
#include "paging.h"
#include "io.h"

// Connect the print library to x86 framebuffer
#define print_char fb_print_char

#define PIT_CHANNEL 0x40
#define PIT_MODE 0x43
#define PIT_0_7_COMMAND 0x20
#define PIT_0_7_DATA 0x21
#define PIT_8_15_COMMAND 0xA0
#define PIT_8_15_DATA 0xA1

#define PIT_RESET 0x20

inline void pit_reset(u1 irq) {
    if (irq >= 8) out1(PIT_8_15_COMMAND, PIT_RESET);
    out1(PIT_0_7_COMMAND, PIT_RESET);
}

#endif
#endif
