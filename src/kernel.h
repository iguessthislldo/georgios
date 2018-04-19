#ifndef KERNEL_HEADER
#define KERNEL_HEADER

#include <library.h>

extern u4 KERNEL_LOW_START;
extern u4 KERNEL_LOW_END;
extern u4 KERNEL_OFFSET;
extern u4 KERNEL_HIGH_START;
extern u4 KERNEL_HIGH_END;
extern u4 KERNEL_SIZE;

#define kernel_offset(a) ((a) + (mem_t) &KERNEL_OFFSET)

typedef u1 Context;

struct Process_struct {
    u1 id;
    bool running;
    void * context;
    void * stack;
};
typedef struct Process_struct Process;

bool scheduler_enabled;
extern void context_switch(void ** old, void * new);
void scheduler();
Context * schedulerc;
Process * currentp;

char * panic_message;
#define PANIC(message) panic_message = (message); asm("int $33");

#endif
