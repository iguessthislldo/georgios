#include <library.h>
#include <print.h>
#include <platform.h>
#include <memory.h>

#include "kernel.h"
#include "pci.h"

char * panic_message = 0;

void kernel_main() {

    memory_init();

    print_string("Booted\n");

    if (ata_disk_read(0, 0)) {
        print_data(&ata_buffer[0], 512);
    } else {
        print_string("Read Failed\n");
    }

#ifndef BOOT_TEST
    while (true) {}
#else
    shutdown();
#endif
}

