#include <library.h>

#include "platform.h"
#include "../platform.h"

void platform_init() {
    fb_initialize();
    gdt_initialize();
    idt_initialize();
    irq_initialize();
}
