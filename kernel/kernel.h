#ifndef KERNEL_HEADER
#define KERNEL_HEADER

#include <library.h>
#include <platform.h>

extern u4 KERNEL_LOW_START;
extern u4 KERNEL_LOW_END;
extern u4 KERNEL_OFFSET;
extern u4 KERNEL_HIGH_START;
extern u4 KERNEL_HIGH_END;
extern u4 KERNEL_SIZE;

#define kernel_offset(a) ((a) + (mem_t) &KERNEL_OFFSET)

typedef struct {
    u1 id;
    bool running;
    bool in_kernelspace;
    void * context;
    void * stack;
} Process;

bool scheduler_enabled;
extern void context_switch(void ** old, void * new);
void scheduler();
void * schedulerc;
Process * currentp;

char * panic_message;

void system_call(arg_t call_number, arg_t argument);

#endif
