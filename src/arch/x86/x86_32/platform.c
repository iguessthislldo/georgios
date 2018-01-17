#include <library.h>

#include "platform.h"
#include "../platform.h"

#define PIT_0_7_COMMAND 0x20
#define PIT_0_7_DATA 0x21
#define PIT_8_15_COMMAND 0xA0
#define PIT_8_15_DATA 0xA1
#define PIT_EOI 0x20

bool platform_init() {
	fb_initialize();
    gdt_initialize();
    idt_initialize();

    return true;
}
