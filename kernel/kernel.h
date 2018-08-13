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
    bool valid;
    mem_t context;
    mem_t stack;
#ifdef PLATFORM_THREAD_MEMBERS
    PLATFORM_THREAD_MEMBERS
#endif
} thread_t;

#define THREAD_COUNT_MAX 4
typedef struct {
    u2 id;
    u1 index;
    bool in_kernelspace;
    u1 thread_count;
    thread_t threads[THREAD_COUNT_MAX];
#ifdef PLATFORM_PROCESS_MEMBERS
    PLATFORM_PROCESS_MEMBERS
#endif
} process_t;

#define PROCESS_COUNT_MAX 255
u1 process_count;
u2 next_process_id;
process_t processes[PROCESS_COUNT_MAX];

mem_t schedulerc;
u1 process_index;
u1 thread_index;

bool scheduler_enabled;
extern void context_switch(mem_t * old, mem_t new);
void scheduler();

char * panic_message;

void system_call(arg_t call_number, arg_t argument);

bool serial_log_enabled;

#endif
