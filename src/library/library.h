#ifndef LIBRARY_HEADER
#define LIBRARY_HEADER

/*
 * Integer Types
 */
typedef char i1;
typedef unsigned char u1;
typedef short i2;
typedef unsigned short u2;
typedef int i4;
typedef unsigned int u4;

/*
 * Floating Point Types
 */
typedef float f32;
typedef double f64;

/*
 * Boolean Type
 */
typedef u1 bool;
#define true 1
#define false 0

/*
 * Utility Functions
 */
u4 strlen(const char * string);
void * memset(void * pointer, i1 value, u4 number);

#endif
