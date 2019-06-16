#ifndef BASIC_TYPES_HEADER
#define BASIC_TYPES_HEADER

#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>

/*
 * Integer Types
 */
#define i1 int8_t
#define u1 uint8_t
#define i2 int16_t
#define u2 uint16_t
#define i4 int32_t
#define u4 uint32_t
#define i8 int64_t
#define u8 uint64_t

/*
 * Address Types
 */
typedef uintptr_t mem_t;
typedef uintptr_t arg_t;

#endif
