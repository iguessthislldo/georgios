#include <library.h>
#include <print.h>
#include <kernel.h>
#include <memory.h>

#include "platform.h"

#include <cga_console.h>

void print_char(char c) {
    x86_32_print_char(c);
}

void shutdown() {
    print_string("Shutting Down...\n");
    out4(0xB004, 0x2000); // Bochs
    out4(0x604, 0x2000); // QEMU
}

enum ACPI_RSDP_Status acpi_rsdp_status = ACPI_RSDP_STATUS_NOT_FOUND;

static inline const char * mb_tag_type_to_str(u4 tag_type) {
    switch (tag_type) {
    case MULTIBOOT_TAG_TYPE_END:
        return "MULTIBOOT_TAG_TYPE_END";
    case MULTIBOOT_TAG_TYPE_CMDLINE:
        return "MULTIBOOT_TAG_TYPE_CMDLINE";
    case MULTIBOOT_TAG_TYPE_BOOT_LOADER_NAME:
        return "MULTIBOOT_TAG_TYPE_BOOT_LOADER_NAME";
    case MULTIBOOT_TAG_TYPE_MODULE:
        return "MULTIBOOT_TAG_TYPE_MODULE";
    case MULTIBOOT_TAG_TYPE_BASIC_MEMINFO:
        return "MULTIBOOT_TAG_TYPE_BASIC_MEMINFO";
    case MULTIBOOT_TAG_TYPE_BOOTDEV:
        return "MULTIBOOT_TAG_TYPE_BOOTDEV";
    case MULTIBOOT_TAG_TYPE_MMAP:
        return "MULTIBOOT_TAG_TYPE_MMAP";
    case MULTIBOOT_TAG_TYPE_VBE:
        return "MULTIBOOT_TAG_TYPE_VBE";
    case MULTIBOOT_TAG_TYPE_FRAMEBUFFER:
        return "MULTIBOOT_TAG_TYPE_FRAMEBUFFER";
    case MULTIBOOT_TAG_TYPE_ELF_SECTIONS:
        return "MULTIBOOT_TAG_TYPE_ELF_SECTIONS";
    case MULTIBOOT_TAG_TYPE_APM:
        return "MULTIBOOT_TAG_TYPE_APM";
    case MULTIBOOT_TAG_TYPE_EFI32:
        return "MULTIBOOT_TAG_TYPE_EFI32";
    case MULTIBOOT_TAG_TYPE_EFI64:
        return "MULTIBOOT_TAG_TYPE_EFI64";
    case MULTIBOOT_TAG_TYPE_SMBIOS:
        return "MULTIBOOT_TAG_TYPE_SMBIOS";
    case MULTIBOOT_TAG_TYPE_ACPI_OLD:
        return "MULTIBOOT_TAG_TYPE_ACPI_OLD";
    case MULTIBOOT_TAG_TYPE_ACPI_NEW:
        return "MULTIBOOT_TAG_TYPE_ACPI_NEW";
    case MULTIBOOT_TAG_TYPE_NETWORK:
        return "MULTIBOOT_TAG_TYPE_NETWORK";
    case MULTIBOOT_TAG_TYPE_EFI_MMAP:
        return "MULTIBOOT_TAG_TYPE_EFI_MMAP";
    case MULTIBOOT_TAG_TYPE_EFI_BS:
        return "MULTIBOOT_TAG_TYPE_EFI_BS";
    case MULTIBOOT_TAG_TYPE_EFI32_IH:
        return "MULTIBOOT_TAG_TYPE_EFI32_IH";
    case MULTIBOOT_TAG_TYPE_EFI64_IH:
        return "MULTIBOOT_TAG_TYPE_EFI64_IH";
    case MULTIBOOT_TAG_TYPE_LOAD_BASE_ADDR:
        return "MULTIBOOT_TAG_TYPE_LOAD_BASE_ADDR";
    default:
        return "Unkown Type";
    }
}

void process_multiboot(u4 * mb_info_ptr) {
    u1 * i = (u1*) (mb_info_ptr + 2);
    u4 type = -1;
    bool got_memory_map = false;
    print_string("Multiboot Tags Available:\n");
    while (type) {
        type = *(u4*)i;
        print_string("  ");
        print_string(mb_tag_type_to_str(type));
        print_char('\n');
        u4 size = *(u4*)(i + 4);

        u4 mmap_entry_size;
        u4 mmap_entry_count;
        struct multiboot_mmap_entry * mmap_entries;

        switch (type) {
        case MULTIBOOT_TAG_TYPE_ACPI_OLD:
            if (acpi_rsdp_status == ACPI_RSDP_STATUS_NOT_FOUND) {
                memcpy(&acpi_rsdp.v1, i + 8, sizeof(ACPI_RSDPv1));
                acpi_rsdp_status = ACPI_RSDP_STATUS_FOUND_V1;
            }
            break;
        case MULTIBOOT_TAG_TYPE_ACPI_NEW:
            if (acpi_rsdp_status == ACPI_RSDP_STATUS_NOT_FOUND ||
                acpi_rsdp_status == ACPI_RSDP_STATUS_FOUND_V1) {
                memcpy(&acpi_rsdp.v2, i + 8, sizeof(ACPI_RSDPv2));
                acpi_rsdp_status = ACPI_RSDP_STATUS_FOUND_V2;
            }
            break;

        case MULTIBOOT_TAG_TYPE_MMAP:
            got_memory_map = true;
            mmap_entry_size = *(u4*)(i + 8);
            mmap_entry_count = (size - 16) / mmap_entry_size;
            mmap_entries = (struct multiboot_mmap_entry*)(i + 16);
            for (u4 e = 0; e < mmap_entry_count; e++) {
                if (mmap_entries[e].type == MULTIBOOT_MEMORY_AVAILABLE) {
                    memory_range_add(
                        mmap_entries[e].addr, mmap_entries[e].len,
                        FRAME_STACK_USE);
                }
            }
            break;

        case MULTIBOOT_TAG_TYPE_CMDLINE:
            print_string("    \"");
            print_string((char*)(i + 8));
            print_string("\"\n");
            break;
        }

        i += ALIGN(size, 8);
    }

    if (!got_memory_map) {
        PANIC("Could not get memory map from multiboot!\n");
    }

    if (acpi_rsdp_status == ACPI_RSDP_STATUS_NOT_FOUND) {
        PANIC("ACPI was not found!\n");
    } else {
        print_format("ACPI is v{s}\nOEM is ",
            acpi_rsdp.v1.revision ? "2 or later" : "1");
        print_stripped_string(acpi_rsdp.v1.oemid, 6);
        print_char('\n');
    }
}

#define COM1 0x3f8
void serial_initialize() {
	out1(COM1 + 1, 0x00); // Disable all interrupts
	out1(COM1 + 3, 0x80); // Enable DLAB (set baud rate divisor)
	out1(COM1 + 0, 0x03); // Set divisor to 3 (lo byte) 38400 baud
	out1(COM1 + 1, 0x00); //                  (hi byte)
	out1(COM1 + 3, 0x03); // 8 bits, no parity, one stop bit
	out1(COM1 + 2, 0xC7); // Enable FIFO, clear them, with 14-byte threshold
	out1(COM1 + 4, 0x0B); // IRQs enabled, RTS/DSR set
	serial_log_enabled = true;
}

void serial_out(char c) {
    while (!(in1(COM1 + 5) & 0x20)) {}
    out1(COM1, c);
}

void platform_init(u4 * mb_info_ptr) {
    kernel_range = 1;
    serial_initialize();
    initialize_cga_console();
    gdt_initialize();
    idt_initialize();
    irq_initialize();
    //ps2_init();
    process_multiboot(mb_info_ptr);
    find_pci_devices();
    enable_interrupts();
}

u4 tick_counter = 0;

void wait(u4 ticks) {
    ticks += tick_counter;
    while (tick_counter != ticks) {
        asm volatile ("nop");
    }
}

void usec_wait(u4 usec) {
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

void msec_wait(u4 msec) {
    usec_wait(msec * 1100);
}

