#ifndef X86_32_PLATFORM_HEADER
#define X86_32_PLATFORM_HEADER

#if defined(__GNUC__) && defined(__i386__)
#define x86_32
#endif

#ifdef x86_32
#define PLATFORM_SUPPORTED

#include "fb.h"
#include "gdt.h"
#include "idt.h"
#include "paging.h"

// Connect the print library to x86 framebuffer
#define print_char fb_print_char

#endif
#endif
