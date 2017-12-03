#include <library.h>

#include "platform.h"
#include "../platform.h"

bool platform_init() {
	fb_initialize();
    gdt_initialize();
    idt_initialize();

    return true;
}
