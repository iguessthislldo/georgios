#ifndef GEORGIOS_BIOS_INT_STDLIB_H
#define GEORGIOS_BIOS_INT_STDLIB_H

#include <stddef.h>

#define malloc georgios_bios_int_malloc
void * malloc(size_t size);

#define calloc georgios_bios_int_calloc
void * calloc(size_t num, size_t size);

#define free georgios_bios_int_free
void free(void * ptr);

#endif
