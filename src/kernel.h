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

/*
struct Context_struct {
    u4 ebp, eip;
};
typedef struct Context_struct Context;
*/
typedef u1 Context;

struct Process_struct {
    u1 id;
    bool running;
    Context * context;
    void * stack;
};
typedef struct Process_struct Process;

extern void context_switch(Context ** old, Context * new);
void scheduler();
Context * schedulerc;
Process * currentp;

#endif
