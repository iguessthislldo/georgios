#include "platform.h"
#include "../platform.h"

platform_init_t platform_init() {
	fb_initialize();
    gdt_initialize();
    idt_initialize();

    return PLATFORM_INIT_SUCCESS;
}
