#include <library.h>
#include <print.h>
#include <platform.h>
#include <memory.h>

#include "kernel.h"
#include "pci.h"

char * panic_message = 0;

extern mem_t setup_process(bool usermode, mem_t eip, mem_t esp);
extern void usermode();

void kernel_main() {

    memory_init();

    print_string("Booted\n");

#ifndef BOOT_TEST
    while (true) {}
#else
    shutdown();
#endif
}

