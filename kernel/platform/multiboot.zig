const builtin = @import("builtin");

const print = @import("../print.zig");
const util = @import("../util.zig");

extern var multiboot_info_pointer: c_ulong;

pub fn initialize() void {
    var i = @intCast(usize, multiboot_info_pointer);
    if (i != 0) {
        print.string("Multiboot Tags:\n");
        i += 8; // Move to first tag
        var kind = @intToPtr(*u32, i).*;
        var size = @intToPtr(*u32, i + 4).*;
        while (kind != 0) {
            switch (kind) {
                1 => {
                    print.string(" - Boot\n");
                },
                6 => {
                    print.string(" - Memory\n");
                },
                10 => {
                    print.string(" - ApmTable\n");
                },
                14 => {
                    print.string(" - Acpi1Rsdp\n");
                },
                15 => {
                    print.string(" - Acpi2Rsdp\n");
                },
                else => {
                    print.format(" - Unknown {}\n", kind);
                },
            }
            // Move to next tag
            i += util.padding(size, 8);
            kind = @intToPtr(*u32, i).*;
            size = @intToPtr(*u32, i + 4).*;
        }
    } else {
        @panic("multiboot_info_pointer is null!");
    }
}
