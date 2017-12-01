#include "platform.h"

bool platform_initialize() {
	fb_initialize();
    gdt_initialize();
    idt_initialize();

    return true;
}
