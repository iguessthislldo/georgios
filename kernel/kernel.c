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

    print_string("Done\n");
    out4(0xB004, 0x2000); // Bochs
    out4(0x604, 0x2000); // QEMU
}

