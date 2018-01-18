#ifndef KERNEL_HEADER
#define KERNEL_HEADER

#include <library.h>

extern u4 KERNEL_LOW_START;
extern u4 KERNEL_LOW_END;
extern u4 KERNEL_OFFSET;
extern u4 KERNEL_HIGH_START;
extern u4 KERNEL_HIGH_END;

#define kernel_offset(a) ((void*) ((a) + (u4) &KERNEL_OFFSET))

#endif
