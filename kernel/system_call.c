#include <kernel.h>
#include <print.h>

void system_call(arg_t call_number, arg_t argument) {
    switch (call_number) {
    case 99:
        print_char((char) argument);
        break;
    default:
        PANIC_CODE(
            "Invalid system call number, labeled above as error code.",
            call_number
        );
    }
}
