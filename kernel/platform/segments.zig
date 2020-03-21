const builtin = @import("builtin");

const Access = packed struct {
    accessed: bool = false,
    /// Readable Flag for Code Selectors, Writable Bit for Data Selectors
    rw: bool = true,
    /// Direction/Conforming Flag
    /// For data selectors sets the direciton of segment growth. I don't think
    /// I care about that. For code selectors true means code in this segment
    /// can be excuted by lower rings.
    dc: bool = false,
    /// True for Code Selectors, False for Data Selectors
    executable: bool = false,
    /// True for Code and Data Segments
    no_system_segment: bool = true,
    /// 0 (User) through 3 (Kernel)
    ring_level: u2 = 0,
    valid: bool = true,
};

const Flags = packed struct {
    always_zero: u2 = 0,
    /// Protected Mode (32 bits) segment if true
    pm: bool = true,
    /// Limit is bytes if this is true, else limit is in pages.
    granularity: bool = true,
};

const Entry = packed struct {
    limit_0_15: u16,
    base_0_15: u16,
    base_16_23: u8,
    access: Access,
    // Highest 4 bits of limit and flags. Was going to have this be two 4 bit
    // fields, but that wasn't the same thing as this for some reason...
    limit_16_19: u8,
    base_24_31: u8,
};
var table: [5]Entry = undefined;

fn set(index: u8, base: u32, limit: u32, access: Access, flags: Flags) u16 {
    table[index].limit_0_15 = @intCast(u16, limit & 0xffff);
    table[index].base_0_15 = @intCast(u16, base & 0xffff);
    table[index].base_16_23 = @intCast(u8, (base >> 16) & 0xff);
    table[index].access = access;
    table[index].limit_16_19 =
        @intCast(u8, (limit >> 16) & 0xf) |
        (@intCast(u8, @bitCast(u4, flags)) << 4);
    table[index].base_24_31 = @intCast(u8, (base >> 24) & 0xff);
    return (index << 3) | access.ring_level;
}

fn set_null_entry(index: u8) void {
    table[index] =
        @bitCast(Entry, @intCast(@IntType(false, @sizeOf(Entry) * 8), 0));
}

const Pointer = packed struct {
    limit: u16,
    base: u32,
};
extern fn gdt_load(pointer: *const Pointer) void;
comptime {
    asm (
        \\ .section .text
        \\ .global gdt_load
        \\ .type gdt_load, @function
        \\ gdt_load:
        \\     movl 4(%esp), %eax
        \\     lgdt (%eax)
        \\     movw (kernel_data_selector), %ax
        \\     movw %ax, %ds
        \\     movw %ax, %es
        \\     movw %ax, %fs
        \\     movw %ax, %gs
        \\     movw %ax, %ss
        \\     pushl (kernel_code_selector)
        \\     push $.gdt_complete_load
        \\     ljmp *(%esp)
        \\   .gdt_complete_load:
        \\     add $8, %esp
        \\     ret
        // \\     movw (tss_selector), %ax
        // \\     ltr %ax
    );
}

pub export var kernel_code_selector: u16 = 0;
pub export var kernel_data_selector: u16 = 0;
pub export var user_code_selector: u16 = 0;
pub export var user_data_selector: u16 = 0;
pub export var tss_selector: u16 = 0;

pub fn initialize() void {
    set_null_entry(0);
    const flags = Flags{};
    kernel_code_selector = set(1, 0, 0xFFFFFFFF,
        Access{.ring_level = 0, .executable = true}, flags);
    kernel_data_selector = set(2, 0, 0xFFFFFFFF,
        Access{.ring_level = 0}, flags);
    user_code_selector = set(3, 0, 0xFFFFFFFF,
        Access{.ring_level = 3, .executable = true}, flags);
    user_data_selector = set(4, 0, 0xFFFFFFFF,
        Access{.ring_level = 3}, flags);
    // set_null_entry(5);

    const pointer = Pointer {
        .limit = @intCast(u16, @sizeOf(@typeOf(table)) - 1),
        .base = @intCast(u32, @ptrToInt(&table)),
    };
    gdt_load(&pointer);
}
