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
#include "irq.h"

// Connect the print library to x86 framebuffer
#define print_char fb_print_char

#define enable_interrupts() asm ("sti");
#define disable_interrupts() asm ("cli");

#endif
#endif
