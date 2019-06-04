#ifndef LIBRARY_HEADER
#define LIBRARY_HEADER

#include <basic_types.h>
#include <stdarg.h>

/*
 * Utility Functions
 */
size_t strlen(const char * string);
void * memset(void * pointer, i1 value, size_t number);
void * memcpy(void * dest, const void * src, size_t size);
bool isspace(char c);
char * strcpy(char * dest, const char * src);

/*
 * Bit Operations
 */
#define GET_BIT(value, n) ((value) & (1 << (n)))
#define SET_BIT(var, n, value) \
    ((value) ? ((var) | (1 << (n))) : ((var) & ~(1 << (n))))
#define BIT_ROUND_MASK(N) ((1 << (N)) - 1)
#define BIT_ROUND_DOWN(VALUE, N) ((VALUE) & ~BIT_ROUND_MASK((N)))
#define BIT_ROUND_UP(VALUE, N) ( \
    ((VALUE) & BIT_ROUND_MASK((N))) ? \
        ((BIT_ROUND_DOWN((VALUE), (N)) >> (N)) + 1) << (N) \
    : \
        BIT_ROUND_DOWN((VALUE), (N)) \
)
#define GET_BYTE(value, n) (((value) >> ((n) * 8)) & 0x000000FF)

/*
 * Math Macros
 */
#define KiB(value) ((value) * (1 << 10))
#define MiB(value) ((value) * (1 << 20))
#define GiB(value) ((value) * (1 << 30))
#define TiB(value) ((value) * (1 << 40))
#define PiB(value) ((value) * (1 << 50))
#define MOD(n, d) ((n) & ((d) - 1))
#define ALIGN(value, alignment) (((value) + (alignment) - 1) & -(alignment))
#define PADDING(value, alignment) (-(value) & ((alignment) - 1))
#define MAX(a, b) ((a) > (b) ? (a) : (b))
#define MIN(a, b) ((a) < (b) ? (a) : (b))

#endif
