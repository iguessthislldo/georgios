#ifndef KERNEL_HEADER
#define KERNEL_HEADER

#include <basic_types.h>
#include <platform.h>

/*
 * System Management
 */

// Message to print during panic
void set_panic_message(const char * message, unsigned size);
const char * panic_message;
u4 panic_message_size;

// Access to System calls
void system_call(arg_t call_number, arg_t argument);

extern mem_t setup_process(bool usermode, mem_t eip, mem_t esp);
extern void context_switch(mem_t * old, mem_t new);
extern void usermode();

#endif
