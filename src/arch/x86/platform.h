/*
 * Determine if this is x86_32 or x86_64
 * Also code that can be used on x86_32 or x86_64
 */

#ifndef X86_PLATFORM_HEADER
#define X86_PLATFORM_HEADER
#ifndef PLATFORM_SUPPORTED

#include "x86_32/platform.h"
/*
#include "x86_64/platform.h"
*/

#ifdef PLATFORM_SUPPORTED
#define x86
#define halt() __asm__ ("cli;hlt\n\t");

/*
 * Varargs
 */
typedef void * va_list;
#define va_start(list, preargument) \
    (list = ((va_list) &preargument) + sizeof(preargument))
#define va_arg(list , type) \
    (*(type*)((list += sizeof(type)) - sizeof(type)))

#endif
#endif
#endif
