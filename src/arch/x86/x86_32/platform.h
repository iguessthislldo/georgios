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

/*
 * Varargs
 */
typedef void * va_list;
#define va_start(list, preargument) list = ((va_list) &preargument) + sizeof(preargument)
#define va_arg(list , type) *((type*)((list += sizeof(type)) - sizeof(type)))

#endif
#endif
