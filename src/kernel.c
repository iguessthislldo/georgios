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

void page_directory_print(u4 index) {
    page_directory_t pd = page_directory_get(index);
    print_format("{d}: ", index);
    if (pd.present) {
        print_format("{x}\n", pd.address);
        print_format("    4 MiB Pages? {d}\n", pd.page_size);
        print_format("    Has been Accessed? {d}\n", pd.accessed);
        print_format("    Cache Disabled? {d}\n", pd.cache_disabled);
        print_format("    Write Through? {d}\n", pd.write_through);
        print_format("    User Accessible? {d}\n", pd.user);
        print_format("    Writable? {d}\n", pd.writable);
    } else {
        print_string("Not Present\n");
    }
}

void direct_paging(u4 address, u4 ammount) {
    
}

// Bochs i386 32 MiB Usable Memory
// 0 -> 0x9f000 - 1
// 0x100000 -> 0x100000 + 0x1ef0000 - 1

void kernel_main() {
    if (!initialize()) {
        print_string("Kernel Failed to Initialize\n");
        halt();
    }
    print_string("Kernel Loaded\n");

    print_hex(&page_directory[0]);
    print_char('\n');

    page_directory_t v;
    v.address = 0xABCDEF11;
    v.present = true;
    page_directory_set(32, v);

    enable_paging();
    disable_paging();

    print_string("Kernel Done\n");
    halt();
}

