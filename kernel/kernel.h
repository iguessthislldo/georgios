#ifndef KERNEL_HEADER
#define KERNEL_HEADER

#include <basic_types.h>
#include <platform.h>

/*
 * Values from Linking
 */
extern u4 _KERNEL_LOW_START;
#define KERNEL_LOW_START ((mem_t) &_KERNEL_LOW_START)
extern u4 _KERNEL_LOW_END;
#define KERNEL_LOW_END ((mem_t) &_KERNEL_LOW_END)
extern u4 _KERNEL_OFFSET;
#define KERNEL_OFFSET ((mem_t) &_KERNEL_OFFSET)
extern u4 _KERNEL_HIGH_START;
#define KERNEL_HIGH_START ((mem_t) &_KERNEL_HIGH_START)
extern u4 _KERNEL_HIGH_END;
#define KERNEL_HIGH_END ((mem_t) &_KERNEL_HIGH_END)
extern u4 _KERNEL_SIZE;
#define KERNEL_SIZE ((mem_t) &_KERNEL_SIZE)

// Convert Lower Kernel Address into Higher Address
#define kernel_offset(a) (((mem_t) a) + KERNEL_OFFSET)

/*
 * System Management
 */

// Message to print during panic
char * panic_message;

// Access to System calls
void system_call(arg_t call_number, arg_t argument);

extern mem_t setup_process(bool usermode, mem_t eip, mem_t esp);
extern void context_switch(mem_t * old, mem_t new);
extern void usermode();

#endif
