#ifndef GEORGIOS_BIOS_INT_STDIO_H
#define GEORGIOS_BIOS_INT_STDIO_H

#include "stdlib.h"

#include <stdarg.h>

#define vsnprintf georgios_bios_int_vsnprintf
extern int vsnprintf(
    char * restrict buffer, size_t bufsz, const char * restrict format, va_list vlist);

#endif
