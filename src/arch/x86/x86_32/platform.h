#ifndef X86_32_PLATFORM_HEADER
#define X86_32_PLATFORM_HEADER

#ifdef __i386__
#define PLATFORM_SUPPORTED
#define x86_32

#include "fb.h"
#include "gdt.h"
#include "idt.h"
#include "paging.h"

// Connect the print library to x86 framebuffer
#define print_char fb_print_char

#endif
#endif
