#ifndef BASIC_TYPES_HEADER
#define BASIC_TYPES_HEADER

#include <stdint.h>
#include <stddef.h>

/*
 * Integer Types
 */
typedef int8_t i1;
typedef uint8_t u1;
typedef int16_t i2;
typedef uint16_t u2;
typedef int32_t i4;
typedef uint32_t u4;
typedef int64_t i8;
typedef uint64_t u8;

/*
 * Floating Point Types
 */
typedef float f4;
typedef double f8;

/*
 * Boolean Type
 */
typedef u1 bool;
#define true 1
#define false 0

/*
 * Address Types
 */
typedef uintptr_t mem_t;
typedef uintptr_t arg_t;

#endif
