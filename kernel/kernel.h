#ifndef KERNEL_HEADER
#define KERNEL_HEADER

#include <library.h>
#include <platform.h>

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

#define kernel_offset(a) (((mem_t) a) + KERNEL_OFFSET)

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
