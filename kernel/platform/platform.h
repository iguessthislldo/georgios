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

#include <library.h>

// Platform Submodules
#include "fb.h"
#include "gdt.h"
#include "idt.h"
#include "paging.h"
#include "io.h"
#include "irq.h"
#include "ps2.h"
#include "pci.h"
#include "ata.h"

// GRUB Multiboot structure
#include "multiboot2.h"

/*
 * Platform initialization, which takes the pointer to system info we got from
 * GRUB as an argument.
 */
void platform_init(u4 * mb_info_ptr);

// Connect the print library to PC framebuffer
#define print_char fb_print_char

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

static inline void usec_wait(u4 usec) {
    for (; usec; usec--) {
        out1(0x80, 0x00);
        out1(0x80, 0x00);
        out1(0x80, 0x00);
        out1(0x80, 0x00);
        out1(0x80, 0x00);
        out1(0x80, 0x00);
        out1(0x80, 0x00);
        out1(0x80, 0x00);
        out1(0x80, 0x00);
        out1(0x80, 0x00);
        out1(0x80, 0x00);
    }
}

static inline void msec_wait(u4 msec) {
    usec_wait(msec * 1100);
}

/* ---------------------------------------------------------------------------
 * Serial Ports
 * ---------------------------------------------------------------------------
 */

// If true, printing will also print to serial
bool serial_log_enabled;

// Output c to COM1
void serial_out(char c);


/* ---------------------------------------------------------------------------
 * ACPI
 * ---------------------------------------------------------------------------
 */
enum ACPI_RSDP_Status {
    ACPI_RSDP_STATUS_NOT_FOUND,
    ACPI_RSDP_STATUS_FOUND_V1,
    ACPI_RSDP_STATUS_FOUND_V2
} acpi_rsdp_status;

typedef struct {
    char signature[8];
    u1 checksum;
    char oemid[6];
    u1 revision;
    u4 rsdt_ptr;
} __attribute__((packed)) ACPI_RSDPv1;

typedef struct {
    ACPI_RSDPv1 v1;
    u4 len;
    u8 xsdt_ptr;
    u1 checksum;
    u1 reserved[3];
} __attribute__((packed)) ACPI_RSDPv2;

union ACPI_RSDP {
    ACPI_RSDPv1 v1;
    ACPI_RSDPv2 v2;
} acpi_rsdp;

#endif
#endif
