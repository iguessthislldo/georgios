/* ===========================================================================
 * x86_32 PC Platform
 * ===========================================================================
 * Exposes an interface for the kernel to initialize and work on a i686 based
 * IBM PC descendent system.
 */
#ifndef X86_32_PLATFORM_HEADER
#define X86_32_PLATFORM_HEADER

#if defined(__GNUC__) && defined(__i386__)
#define x86_32
#define GEORGIOS_IS_32_BIT
#define GEORGIOS_IS_LITTLE_ENDIAN

#include <library.h>

// Platform Submodules
#include "fb.h"
#include "gdt.h"
#include "idt.h"
#include "paging.h"
#include "io.h"
#include "irq.h"
#include "ps2.h"

// GRUB Multiboot structure
#include "multiboot.h"

/*
 * Types for this Platform
 */
typedef u8 max_t; // Max Type
typedef u4 mem_t; // Pointer Type
typedef u4 arg_t; // Generic Argument Type

/*
 * Platform initialization, which takes the pointer to system info we got from
 * GRUB as an argument.
 */
void platform_init(multiboot_info_t* mbd);

// Connect the print library to PC framebuffer
#define print_char fb_print_char

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
    asm("pushl $0\n\tint $50");
#define PANIC_CODE(message, code) \
    panic_message = (message); \
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
