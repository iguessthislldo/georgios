#ifndef LIBRARY_HEADER
#define LIBRARY_HEADER

/*
 * Integer Types
 * TODO: Check/do based on Compiler
 */
typedef char i1;
typedef unsigned char u1;
typedef short i2;
typedef unsigned short u2;
typedef long i4;
typedef unsigned long u4;
typedef long long i8;
typedef unsigned long u8;

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
 * Utility Functions
 */
u4 strlen(const char * string);
void * memset(void * pointer, i1 value, u4 number);
void * memcpy(void * dest, const void * src, u4 size);

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

/*
 * Varargs
 */
#if defined(__GNUC__)
typedef __builtin_va_list va_list;
#define va_start(list, preargument) __builtin_va_start(list, preargument)
#define va_arg(list, type) __builtin_va_arg(list, type)
#else
typedef void * va_list;
#define va_start(list, preargument) list = ((va_list) &preargument) + sizeof(preargument)
#define va_arg(list , type) *((type*)((list += sizeof(type)) - sizeof(type)))
#endif

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
