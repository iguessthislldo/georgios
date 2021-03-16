// Code for managing up the Global Descriptor Table (GDT) and related data
// structures.
//
// We must define the segment selectors required 80286 memory protection scheme
// and also the Task State Segment (TSS) required for context switching.
//
// For Reference See:
//   Intel® 64 and IA-32 Architectures Software Developer’s Manual
//   https://wiki.osdev.org/Global_Descriptor_Table
//   https://wiki.osdev.org/Segmentation

const builtin = @import("builtin");

const print = @import("../print.zig");
const kutil = @import("../util.zig");
const zero_init = kutil.zero_init;

const platform = @import("platform.zig");
const kernel_to_virtual = platform.kernel_to_virtual;

const TaskStateSegment = packed struct {
    link: u16 = 0,
    zero1: u16 = 0,
    esp0: u32 = 0,
    ss0: u16 = 0,
    zero2: u16 = 0,
    esp1: u32 = 0,
    ss1: u16 = 0,
    zero3: u16 = 0,
    esp2: u32 = 0,
    ss2: u16 = 0,
    zero4: u16 = 0,
    cr3: u32 = 0,
    eip: u32 = 0,
    eflags: u32 = 0,
    eax: u32 = 0,
    ecx: u32 = 0,
    edx: u32 = 0,
    ebx: u32 = 0,
    esp: u32 = 0,
    ebp: u32 = 0,
    esi: u32 = 0,
    edi: u32 = 0,
    es: u16 = 0,
    zero5: u16 = 0,
    cs: u16 = 0,
    zero6: u16 = 0,
    ss: u16 = 0,
    zero7: u16 = 0,
    ds: u16 = 0,
    zero8: u16 = 0,
    fs: u16 = 0,
    zero9: u16 = 0,
    gs: u16 = 0,
    zero10: u16 = 0,
    ldt_selector: u16 = 0,
    zero11: u16 = 0,
    trap: bool = false,
    zero12: u15 = 0,
    io_map: u16 = 0,
};
var task_state_segment = TaskStateSegment{};

pub fn set_usermode_interrupt_stack(esp: u32) void {
    task_state_segment.esp0 = esp;
    task_state_segment.ss0 = kernel_data_selector;
}

const Access = packed struct {
    accessed: bool = false,
    /// Readable Flag for Code Selectors, Writable Bit for Data Selectors
    rw: bool = true,
    /// Direction/Conforming Flag
    /// For data selectors sets the direction of segment growth. I don't think
    /// I care about that. For code selectors true means code in this segment
    /// can be executed by lower rings.
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
var table: [6]Entry = undefined;

pub var names: [table.len][]const u8 = undefined;

pub fn get_name(index: u32) []const u8 {
    return if (index < names.len) names[index] else
        "Selector index is out of range";
}

fn set(name: []const u8, index: u8, base: u32, limit: u32,
        access: Access, flags: Flags) u16 {
    names[index] = name;
    print.debug_format("   - [{}]: \"{}\" ", .{index, name});
    if (access.valid) {
        print.debug_format("\n     - starts at {:a}, size is {:x} {}, {} Ring {} ", .{
            base, limit,
            if (flags.granularity) @as([]const u8, "b") else @as([]const u8, "pages"),
            if (flags.pm) @as([]const u8, "32b") else @as([]const u8, "16b"),
            @intCast(usize, access.ring_level)});
        if (access.no_system_segment) {
            if (access.executable) {
                print.debug_format(
                    "Code Segment\n" ++
                    "     - Can{} be read by lower rings.\n" ++
                    "     - Can{} be executed by lower rings\n", .{
                    if (access.rw) @as([]const u8, "") else @as([]const u8, " NOT"),
                    if (access.dc) @as([]const u8, "") else @as([]const u8, " NOT")});
            } else {
                print.debug_format(
                    "Data Segment\n" ++
                    "     - Can{} be written to by lower rings.\n" ++
                    "     - Grows {}.\n", .{
                    if (access.rw) @as([]const u8, "") else @as([]const u8, " NOT"),
                    if (access.dc) @as([]const u8, "down") else @as([]const u8, "up")});
            }
        } else {
            print.debug_string("System Segment\n");
        }
        if (access.accessed) {
            print.debug_string("     - Accessed\n");
        }
    } else {
        print.debug_char('\n');
    }
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
    _ = set("Null", index, 0, 0, zero_init(Access), zero_init(Flags));
    names[index] = "Null";
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
        \\     movw (tss_selector), %ax
        \\     ltr %ax
        \\     add $8, %esp
        \\     ret
    );
}

pub export var kernel_code_selector: u16 = 0;
pub export var kernel_data_selector: u16 = 0;
pub export var user_code_selector: u16 = 0;
pub export var user_data_selector: u16 = 0;
pub export var tss_selector: u16 = 0;

pub fn initialize() void {
    print.debug_string(" - Filling the Global Descriptor Table (GDT)\n");
    set_null_entry(0);
    const flags = Flags{};
    kernel_code_selector = set("Kernel Code", 1, 0, 0xFFFFFFFF,
        Access{.ring_level = 0, .executable = true}, flags);
    kernel_data_selector = set("Kernel Data", 2, 0, 0xFFFFFFFF,
        Access{.ring_level = 0}, flags);
    user_code_selector = set("User Code", 3, 0, kernel_to_virtual(0) - 1,
        Access{.ring_level = 3, .executable = true}, flags);
    user_data_selector = set("User Data", 4, 0, kernel_to_virtual(0) - 1,
        Access{.ring_level = 3}, flags);
    tss_selector = set("Task State", 5, @ptrToInt(&task_state_segment),
        @sizeOf(TaskStateSegment) - 1,
        // TODO: Make This Explicit
        @bitCast(Access, @as(u8, 0xe9)),
        @bitCast(Flags, @as(u4, 0)));

    const pointer = Pointer {
        .limit = @intCast(u16, @sizeOf(@TypeOf(table)) - 1),
        .base = @intCast(u32, @ptrToInt(&table)),
    };
    gdt_load(&pointer);
}
