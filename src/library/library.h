#ifndef LIBRARY_HEADER
#define LIBRARY_HEADER

/*
 * Integer Types
 */
typedef char i8;
typedef unsigned char u8;
typedef short i16;
typedef unsigned short u16;
typedef int i32;
typedef unsigned int u32;

/*
 * Floating Point Types
 */
typedef float f32;
typedef double f64;

/*
 * Boolean Type
 */
typedef u8 bool;
#define true 1
#define false 0

/*
 * Utility Functions
 */
u32 strlen(const char * string);
void * memset(void * pointer, i8 value, u32 number);

#endif
