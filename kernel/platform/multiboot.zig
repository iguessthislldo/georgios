const builtin = @import("builtin");

const print = @import("../print.zig");
const Kernel = @import("../kernel.zig").Kernel;
const util = @import("../util.zig");

extern var multiboot_info_pointer: c_ulong;

const Error = error {
    NullMultibootInfoPointer
};

pub fn initialize(kernel: *Kernel) Error!void {
    var i = @intCast(usize, multiboot_info_pointer);
    if (i == 0) {
        return Error.NullMultibootInfoPointer;
    }
    print.string("Multiboot Tags:\n");
    var tag_count: usize = 0;
    i += 8; // Move to first tag
    var kind = @intToPtr(*u32, i).*;
    var size = @intToPtr(*u32, i + 4).*;
    while (kind != 0) {
        switch (kind) {
            1 => {
                print.string(" - Boot Command (Ignored)\n");
            },
            2 => {
                print.string(" - Boot Loader Name(Ignored)\n");
            },
            4 => {
                print.string(" - Basic Memory (Ignored)\n");
            },
            3 => {
                print.string(" - Modules (Ignored)\n");
            },
            5 => {
                print.string(" - BIOS Boot Device (Ignored)\n");
            },
            6 => {
                print.string(" - Memory Ranges (Ignored)\n");
            },
            7 => {
                print.string(" - VBE Info (Ignored)\n");
            },
            8 => {
                print.string(" - Framebuffer Info (Ignored)\n");
            },
            9 => {
                print.string(" - ELF Symbols (Ignored)\n");
            },
            10 => {
                print.string(" - APM Table (Ignored)\n");
            },
            11 => {
                print.string(" - EFI 32-bit Table Pointer (Ignored)\n");
            },
            12 => {
                print.string(" - EFI 64-bit Table Pointer (Ignored)\n");
            },
            13 => {
                print.string(" - SMBIOS Tables (Ignored)\n");
            },
            14 => {
                print.string(" - ACPI v1 RSDP (Ignored)\n");
            },
            15 => {
                print.string(" - ACPI v2 RSDP (Ignored)\n");
            },
            16 => {
                print.string(" - Networking Info (Ignored)\n");
            },
            17 => {
                print.string(" - EFI Memory Map (Ignored)\n");
            },
            18 => {
                print.string(" - EFI Boot Services Not Terminated (Ignored)\n");
            },
            19 => {
                print.string(" - EFI 32-bit Image Handle Pointer (Ignored)\n");
            },
            20 => {
                print.string(" - EFI 64-bit Image Handle Pointer (Ignored)\n");
            },
            21 => {
                print.string(" - Image Load Base Physical Address (Ignored)\n");
            },
            else => {
                print.format(" - Unknown {} (Ignored)\n", kind);
            },
        }
        // Move to next tag
        i += util.alignment(size, 8);
        kind = @intToPtr(*u32, i).*;
        size = @intToPtr(*u32, i + 4).*;
        tag_count += 1;
    }
    print.format("That was {} tags\n", tag_count);
}
