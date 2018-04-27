#include <kernel.h>

void system_call(arg_t call_number, arg_t argument) {
    breakpoint();
    switch (call_number) {
    default:
        PANIC_CODE(
            "Invalid system call number, labeled above as error code.",
            call_number
        );
    }
}

