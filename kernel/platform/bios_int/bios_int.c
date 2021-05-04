/*
 * Most of the code in this file is written completely from scratch, but some
 * of it is based on code in https://forum.osdev.org/viewtopic.php?f=1&t=31388
 * which helped me transition from using XFree86/X.org's libx86emu to using
 * Steffen Winterfeldt's libx86emu.
 */

#include <x86emu.h>

#include <time.h>
#include <stdlib.h>
#include <sys/io.h>
#include <stdio.h>
#include <georgios_bios_int.h>

#include <stdbool.h>

// We could implement this roughly for x86emu using our rdtsc-based timer, but
// this can be a nop because we don't ask x86emu to have a timeout.
time_t time(time_t * arg) {
    if (arg) {
        *arg = 0;
    }
    return 0;
}

// TODO: Right now this basically just copies format to the buffer
// Doesn't seem to be used for traces though, so it will probably stay like
// this unless I see a message with printf format markers in it.
int vsnprintf(
        char * restrict buffer, size_t bufsz, const char * restrict format, va_list vlist) {
    if (bufsz == 0) return 0;
    size_t buffer_i = 0;
    for (size_t fmt_i = 0; format[fmt_i]; fmt_i++) {
        if (buffer_i == bufsz - 1) {
            break;
        }
        const ch = format[fmt_i];
        buffer[buffer_i] = ch;
        buffer_i++;
    }
    buffer[buffer_i] = '\0';
    return buffer_i;
}

extern void georgios_bios_int_fush_log_impl(char * buf, unsigned size);
void georgios_bios_int_fush_log(x86emu_t * emu, char * buf, unsigned size) {
    georgios_bios_int_fush_log_impl(buf, size);
}

unsigned georgios_bios_int_memio(x86emu_t * emu, uint32_t addr, uint32_t * val, unsigned type) {
    unsigned value = 0xffffffff;
    uint32_t size = type & 0xff;
    type &= ~0xff;
    if (type == X86EMU_MEMIO_R || type == X86EMU_MEMIO_X) {
        if (size & X86EMU_MEMIO_16) {
            value = georgios_bios_int_rdw(addr);
        } else if (size & X86EMU_MEMIO_32) {
            value = georgios_bios_int_rdl(addr);
        } else {
            value = georgios_bios_int_rdb(addr);
        }
        *val = value;
    } else if (type & X86EMU_MEMIO_W) {
        if (size & X86EMU_MEMIO_16) {
            georgios_bios_int_wrw(addr, *val);
        } else if (size & X86EMU_MEMIO_32) {
            georgios_bios_int_wrl(addr, *val);
        } else {
            georgios_bios_int_wrb(addr, *val);
        }
    } else if (type & X86EMU_MEMIO_I) {
        if (size & X86EMU_MEMIO_16) {
            value = inw(addr);
        } else if (size & X86EMU_MEMIO_32) {
            value = inl(addr);
        } else {
            value = inb(addr);
        }
        *val = value;
    } else if (type & X86EMU_MEMIO_O) {
        if (size & X86EMU_MEMIO_16) {
            outw(addr, *val);
        } else if (size & X86EMU_MEMIO_32) {
            outl(addr, *val);
        } else {
            outb(addr, *val);
        }
    } else {
        georgios_bios_int_print_string("georgios_bios_int_memio invalid type is ");
        georgios_bios_int_print_value(type);
        georgios_bios_int_print_string("\n");
        return 1;
    }
    return 0;
}

int georgios_bios_int_code_check(x86emu_t * emu) {
    // TODO: This shouldn't be needed, but it looks like switching the VESA
    // mode doesn't work properly if we run the interrupt without either this
    // or tracing.
    georgios_bios_int_wait();
    return 0;
}

static x86emu_t * emu;
static bool georgios_bios_int_trace;

void georgios_bios_int_init(bool trace) {
    georgios_bios_int_trace = trace;
    const unsigned allow_all = X86EMU_PERM_R | X86EMU_PERM_W | X86EMU_PERM_X;
    emu = x86emu_new(allow_all, allow_all);
    x86emu_set_memio_handler(emu, georgios_bios_int_memio);
    emu->io.iopl_ok = 1;
    x86emu_set_log(emu, 1024, georgios_bios_int_fush_log);
    if (trace) {
        emu->log.trace = X86EMU_TRACE_DEFAULT;
    }
}

bool georgios_bios_int_run(GeorgiosBiosInt * params) {
    emu->x86.R_EAX = params->eax;
    emu->x86.R_EBX = params->ebx;
    emu->x86.R_ECX = params->ecx;
    emu->x86.R_EDX = params->edx;
    emu->x86.R_EDI = params->edi;

    const uint16_t ip = 0x600;
    emu->x86.R_IP = ip;
    x86emu_set_seg_register(emu, emu->x86.R_CS_SEL, 0);
    *(uint8_t*)(ip + 0) = 0xcd; // int ...
    *(uint8_t*)(ip + 1) = params->interrupt; // Interrupt Number
    *(uint8_t*)(ip + 2) = 0xf4; // hlt

    emu->x86.R_SP = 0x4000;
    x86emu_set_seg_register(emu, emu->x86.R_SS_SEL, 0);

    bool slow = params->slow && !georgios_bios_int_trace;
    if (slow) {
        x86emu_set_code_handler(emu, georgios_bios_int_code_check);
    }

    const unsigned result = x86emu_run(emu, X86EMU_RUN_LOOP);

    if (slow) {
        x86emu_set_code_handler(emu, NULL);
        params->slow = false;
    }

    params->eax = emu->x86.R_EAX;
    params->ebx = emu->x86.R_EBX;
    params->ecx = emu->x86.R_ECX;
    params->edx = emu->x86.R_EDX;

    if (result) {
        georgios_bios_int_print_string("georgios_bios_int_run: result is ");
        georgios_bios_int_print_value(result);
        georgios_bios_int_print_string("\n");
        return true;
    }

    return false;
}

void georgios_bios_int_done() {
    x86emu_done(emu);
}
