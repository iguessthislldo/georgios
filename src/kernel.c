#include <library.h>
#include <print.h>
#include <platform.h>

#define TEST_RESULT(result)\
    print_string((result) ? "OK\n" : "FAILED\n");\
    if (!(result)) { return false; }

bool initialize() {
    bool r;

    // Platform
    r = platform_init();
    print_string("Initialized Platform... ");
    TEST_RESULT(r);

    return true;
}

void kernel_main() {
    if (!initialize()) {
        print_string("Kernal Failed to Initialize\n");
        halt();
    }
    print_string("Kernal Loaded\n");

    print_format("Page Directory: %u\n", &page_directory);

    print_string("Kernal Done\n");
    halt();
}

