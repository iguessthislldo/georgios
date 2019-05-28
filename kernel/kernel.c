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

#ifndef BOOT_TEST
    while (true) {}
#else
    shutdown();
#endif
}

