const builtin = @import("builtin");

const utils = @import("utils");

const paging = @import("paging.zig");
const platform = @import("platform.zig");
const vbe = @import("vbe.zig");

const kernel = @import("root").kernel;
const print = kernel.print;
const Range = kernel.memory.Range;

export var multiboot_info: []u32 = undefined;

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
        return utils.int_to_enum(TagKind, value);
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

/// Process part of the Multiboot information given by `find`. If `find` wasn't
/// found, returns `Error.TagNotFound`. If `find` is `End`, then just list
/// what's in the Multiboot header.
pub fn find_tag(find: TagKind) Error!Range {
    var i = @intCast(usize, @ptrToInt(multiboot_info.ptr));
    if (i == 0) {
        return Error.NullMultibootInfoPointer;
    }
    const list = find == .End;
    if (list) {
        print.debug_string(" - Multiboot Tags Available:\n");
    }
    var running = true;
    var tag_count: usize = 0;
    if (list) {
        const size = @intToPtr(*u32, i).*;
        print.debug_format(
            \\   - Total Size: {} B ({} KiB)
            \\   - Tags:
            \\
            , .{size, size >> 10});
    }
    i += 8; // Move to first tag
    while (running) {
        const kind_raw = @intToPtr(*u32, i).*;
        const size = @intToPtr(*u32, i + 4).*;
        const kind_maybe = TagKind.from_u32(kind_raw);
        if (list) {
            print.debug_format("     - {}\n", .{
                if (kind_maybe) |kind|
                    kind.to_string()
                else
                    "Unkown"});
        }
        if (kind_maybe) |kind| {
            if (kind == .End) {
                running = false;
            }
            if (find == kind) {
                return Range{.start = i, .size = size};
            }
        }
        // Move to next tag
        i += utils.align_up(size, 8);
        tag_count += 1;
    }
    if (list) {
        print.debug_format("   - That was {} tags\n", .{tag_count});
        return Range{.start = i, .size = 0};
    }
    return Error.TagNotFound;
}

const VbeInfo = packed struct {
    kind: TagKind,
    size: u32,
    mode: u16,
    interface_seg: u16,
    interface_off: u16,
    interface_len: u16,
    control_info: [512]u8,
    mode_info: [256]u8,
};

pub fn get_vbe_info() ?*VbeInfo {
    const range = find_tag(TagKind.Vbe) catch {
        return null;
    };
    return range.to_ptr(*VbeInfo);
}
