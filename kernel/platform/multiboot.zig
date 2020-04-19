const builtin = @import("builtin");

const print = @import("../print.zig");
const Kernel = @import("../kernel.zig").Kernel;
const RealMemoryMap = @import("../memory.zig").RealMemoryMap;
const util = @import("../util.zig");

export var multiboot_info_pointer: u32 = 0;

const Error = error {
    NullMultibootInfoPointer,
    TagNotFound,
};

const TagKind = enum (u32) {
    End = 0,
    CmdLine = 1,
    BootLoaderName = 2,
    Module = 3,
    BasicMemInfo = 4,
    BootDev = 5,
    Mmap = 6,
    Vbe = 7,
    Framebuffer = 8,
    ElfSections = 9,
    Apm = 10,
    Efi32 = 11,
    Efi64 = 12,
    Smbios = 13,
    AcpiOld = 14,
    AcpiNew = 15,
    Network = 16,
    EfiMmap = 17,
    EfiBs = 18,
    Efi32Ih = 19,
    Efi64Ih = 20,
    LoadBaseAddr = 21,

    pub fn from_u32(value: u32) ?TagKind {
        return util.int_to_enum(TagKind, value);
    }

    pub fn to_string(self: TagKind) []const u8 {
        return switch (self) {
            .End => "End",
            .CmdLine => "Boot Command",
            .BootLoaderName => "Boot Loader Name",
            .Module => "Modules",
            .BasicMemInfo => "Basic Memory Info",
            .BootDev => "BIOS Boot Device",
            .Mmap => "Memory Map",
            .Vbe => "VBE Info",
            .Framebuffer => "Framebuffer Info",
            .ElfSections => "ELF Symbols",
            .Apm => "APM Table",
            .Efi32 => "EFI 32-bit Table Pointer",
            .Efi64 => "EFI 64-bit Table Pointer",
            .Smbios => "SMBIOS Tables",
            .AcpiOld => "ACPI v1 RSDP",
            .AcpiNew => "ACPI v2 RSDP",
            .Network => "Networking Info",
            .EfiMmap => "EFI Memory Map",
            .EfiBs => "EFI Boot Services Not Terminated",
            .Efi32Ih => "EFI 32-bit Image Handle Pointer",
            .Efi64Ih => "EFI 64-bit Image Handle Pointer",
            .LoadBaseAddr => "Image Load Base Physical Address",
        };
    }
};

fn process_mmap(kernel: *Kernel, tag_start: usize, tag_size: usize) void {
    var map = RealMemoryMap{};
    const entry_size = @intToPtr(*u32, tag_start + 8).*;
    const entries_end = tag_start + tag_size;
    var entry_ptr = tag_start + 16;
    while (entry_ptr < entries_end) : (entry_ptr += entry_size) {
    if (@intToPtr(*u32, entry_ptr + 16).* == 1) {
        map.add_range(
            @intCast(usize, @intToPtr(*u64, entry_ptr).*),
            @intCast(usize, @intToPtr(*u64, entry_ptr + 8).*));
    }
    }
    kernel.memory.initialize(&map);
    // TODO: Save Multiboot Structure For Now
    // TODO: Reclaim space of low_stack
    // TODO: Unmap low kernel
}

/// Process part of the Multiboot information given by `find`. If `find` wasn't
/// found, returns `Error.TagNotFound`. If `find` is `End`, then just list
/// what's in the Multiboot header.
pub fn process_tag(kernel: *Kernel, find: TagKind) Error!void {
    var i = @intCast(usize, multiboot_info_pointer);
    if (i == 0) {
        return Error.NullMultibootInfoPointer;
    }
    const list = find == .End;
    if (list) {
        print.string(
            " - Multiboot Tags Available:\n" ++
            "   - Tags:\n");
    }
    var running = true;
    var tag_count: usize = 0;
    var tag_found = false;
    i += 8; // Move to first tag
    while (running) {
        const kind_raw = @intToPtr(*u32, i).*;
        const size = @intToPtr(*u32, i + 4).*;
        const kind_maybe = TagKind.from_u32(kind_raw);
        if (list) {
            print.format("     - {}\n",
                if (kind_maybe) |kind|
                    kind.to_string()
                else
                    "Unkown");
        }
        if (kind_maybe) |kind| {
            if (kind == find) {
                tag_found = true;
            }
            if (kind == .End) {
                running = false;
            }
            switch (kind) {
                .Mmap => {
                    if (find == .Mmap) {
                        process_mmap(kernel, i, size);
                    }
                },
                else => {
                    // Ignored
                },
            }
        }
        // Move to next tag
        i += util.align_up(size, 8);
        tag_count += 1;
    }
    if (list) {
        print.format("   - That was {} tags\n", tag_count);
    }
    if (!tag_found) {
        return Error.TagNotFound;
    }
}
