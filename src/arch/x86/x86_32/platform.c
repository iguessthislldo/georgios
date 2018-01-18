#include <library.h>

#include "platform.h"
#include "../platform.h"

void pit_initialize() {
#define _ "\n\t.word 0x00eb, 0x00eb\n\t"
    asm(
        // Start Initialize
        "mov $0x11, %al\n\t"
        "out %al, $0x20" _
        "out %al, $0xA0" _

        // Remap Interupts
        "mov $0x20, %al\n\t"
        "out %al, $0x21" _
        "mov $0x28, %al\n\t"
        "out %al, $0xA1" _
        
        // Set Master and Slave
        "mov $0x4, %al\n\t"
        "out %al, $0x21" _
        "mov $0x2, %al\n\t"
        "out %al, $0xA1" _

        "mov $0x01, %al\n\t"
        "out %al, $0x21" _
        "out %al, $0xA1" _

        "mov $0x00, %al\n\t"
        "out %al, $0x21" _
        "out %al, $0xA1" _
    );

    // Timer?
    out1(PIT_MODE, 0x34);
    out1(PIT_CHANNEL, 0xFF);
    out1(PIT_CHANNEL, 0xFF);
}

bool platform_init() {
	fb_initialize();
    gdt_initialize();
    idt_initialize();
    pit_initialize();

    return true;
}
