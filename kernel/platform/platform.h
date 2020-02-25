/* ===========================================================================
 * x86_32 PC Platform
 * ===========================================================================
 * Exposes an interface for the kernel to initialize and work on a i686 based
 * IBM PC descendent system.
 */
#ifndef X86_32_PLATFORM_HEADER
#define X86_32_PLATFORM_HEADER

#if defined(__GNUC__) && defined(__i386__)

#define CPU_IS_X86_32
#define CPU_IS_32_BITS
#define CPU_IS_LITTLE_ENDIAN

#include <basic_types.h>

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
#define KERNEL_SIZE (KERNEL_LOW_END - KERNEL_LOW_START)

// Convert Lower Kernel Address into Higher Address
#define kernel_offset(a) (((mem_t) a) + KERNEL_OFFSET)

void print_char(char);

// Platform Submodules
#include "gdt.h"
#include "idt.h"
#include "paging.h"
#include "io.h"
#include "irq.h"
#include "ps2.h"

// GRUB Multiboot structure
#include "multiboot2.h"

void serial_initialize();
void process_multiboot(u4 * mb_info_ptr);

void shutdown();

/* ---------------------------------------------------------------------------
 * Lock
 * ---------------------------------------------------------------------------
 */
typedef u4 lock_t;
#define UNLOCKED 0
#define LOCKED 1

/*
 * Try to atomically acquire the lock at the "lock" pointer.
 * returns false if the lock is acquired, else true (designed for loops).
 */
extern bool attempt_lock(lock_t * lock);

/*
 * Release the lock
 */
inline void release_lock(lock_t * lock) {
    *lock = UNLOCKED;
}

/* ---------------------------------------------------------------------------
 * System Control
 * ---------------------------------------------------------------------------
 */

#define PANIC(message) \
    panic_message = (message); \
    panic_message_size = -1; \
    asm("pushl $0\n\tint $50");
#define PANIC_CODE(message, code) \
    panic_message = (message); \
    panic_message_size = -1; \
    asm("pushl %0\n\tint $50" :: "r" ((code)));

#define enable_interrupts() asm ("sti");
#define disable_interrupts() asm ("cli");
#define halt() __asm__("cli;hlt\n\t")
#define breakpoint() __asm__("xchgw %bx, %bx")

// Frequency of Tick Increment in Hertz
#define TICK_FREQUENCY 100
// Ticks
u4 tick_counter;
// Loop for this many ticks
void wait(u4 ticks);

void usec_wait(u4 usec);
void msec_wait(u4 msec);

/* ---------------------------------------------------------------------------
 * Serial Ports
 * ---------------------------------------------------------------------------
 */

// If true, printing will also print to serial
bool serial_log_enabled;

// Output c to COM1
void serial_out(char c);

#endif
#endif
