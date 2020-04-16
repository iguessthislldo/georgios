const builtin = @import("builtin");
const print = @import("../print.zig");
// const segments = @import("segments.zig");
// const kernel_code_selector = segments.kernel_code_selector;
// const user_code_selector = segments.user_code_selector;

// ===========================================================================
// Interrupt Handlers Defined in idt_handlers.s
// ===========================================================================

// Hardware Interrupt Handlers
extern fn ih_0() void;
extern fn ih_1() void;
extern fn ih_2() void;
extern fn ih_3() void;
extern fn ih_4() void;
extern fn ih_5() void;
extern fn ih_6() void;
extern fn ih_7() void;
extern fn ih_8() void;
extern fn ih_9() void;
extern fn ih_10() void;
extern fn ih_11() void;
extern fn ih_12() void;
extern fn ih_13() void;
extern fn ih_14() void;
extern fn ih_15() void;
extern fn ih_16() void;
extern fn ih_17() void;
extern fn ih_18() void;
extern fn ih_19() void;
extern fn ih_20() void;
extern fn ih_21() void;
extern fn ih_22() void;
extern fn ih_23() void;
extern fn ih_24() void;
extern fn ih_25() void;
extern fn ih_26() void;
extern fn ih_27() void;
extern fn ih_28() void;
extern fn ih_29() void;
extern fn ih_30() void;
extern fn ih_31() void;

// Software Interrupt Handlers
extern fn ih_panic() void;
extern fn ih_system_call() void;

// ===========================================================================
// Interrupt Descriptor Table
// ===========================================================================

const Entry = packed struct {
    offset_0_15: u16 = 0,
    selector: u16 = 0,
    zero: u8 = 0,
    flags: u8 = 0,
    offset_16_31: u16 = 0,
};
var table = table_init: {
    var entries: [256]Entry = undefined;
    for (entries) |*e| {
        e.* = Entry{};
    }
    break :table_init entries;
};

const invalid_index = "Interrupt number is invalid";
var names = names_init: {
    var the_names: [table.len][]const u8 = undefined;
    for (the_names) |*i| {
        i.* = invalid_index;
    }
    break :names_init the_names;
};

pub fn get_name(index: u32) []const u8 {
    return if (index < names.len) names[index] else
        invalid_index ++ " and out of range";
}

const TablePointer = packed struct {
    limit: u16,
    base: u32,
};
var table_pointer: TablePointer = undefined;

fn load() void {
    asm volatile ("lidtl (%[p])" : : [p] "{ax}" (&table_pointer));
}

fn set(name: []const u8, index: u8, handler: extern fn() void, selector: u16, flags: u8) void {
    const offset: u32 = @ptrToInt(handler);
    names[index] = name;
    print.format(
        "   - [{}]: \"{}\"\n" ++
        "     - selector: {:x} address: {:a} flags: {:x}\n",
        index, name, selector, offset,  flags);
    // TODO: Print flag and selector meanings
    table[index].offset_0_15 = @intCast(u16, offset & 0xffff);
    table[index].offset_16_31= @intCast(u16, (offset & 0xffff0000) >> 16);
    table[index].selector = selector;
    table[index].flags = flags;
}

// TODO: Figure out what these are...
const kernel_flags: u8 = 0x8e;
const user_flags: u8 = kernel_flags | (3 << 5);

pub fn initialize() void {
    table_pointer.limit = @sizeOf(Entry) * table.len;
    table_pointer.base = @ptrToInt(&table);
    const kernel_code_selector = @import("segments.zig").kernel_code_selector;

    print.string(" - Filling the Interrupt Descriptor Table (IDT)\n");

    set("Divide by Zero Fault",
        0,  ih_0,  kernel_code_selector, kernel_flags);
    set("Debug Trap",
        1,  ih_1,  kernel_code_selector, kernel_flags);
    set("Nonmaskable Interrupt",
        2,  ih_2,  kernel_code_selector, kernel_flags);
    set("Breakpoint Trap",
        3,  ih_3,  kernel_code_selector, kernel_flags);
    set("Overflow Trap",
        4,  ih_4,  kernel_code_selector, kernel_flags);
    set("Bounds Fault",
        5,  ih_5,  kernel_code_selector, kernel_flags);
    set("Invalid Opcode",
        6,  ih_6,  kernel_code_selector, kernel_flags);
    set("Device Not Available",
        7,  ih_7,  kernel_code_selector, kernel_flags);
    set("Double Fault",
        8,  ih_8,  kernel_code_selector, kernel_flags);
    set("Coprocessor Segment Overrun",
        9,  ih_9,  kernel_code_selector, kernel_flags);
    set("Invalid TSS",
        10, ih_10, kernel_code_selector, kernel_flags);
    set("Segment Not Present",
        11, ih_11, kernel_code_selector, kernel_flags);
    set("Stack-Segment Fault",
        12, ih_12, kernel_code_selector, kernel_flags);
    set("General Protection Fault",
        13, ih_13, kernel_code_selector, kernel_flags);
    set("Page Fault",
        14, ih_14, kernel_code_selector, kernel_flags);
    set("Reserved",
        15, ih_15, kernel_code_selector, kernel_flags);
    set("x87 Floating-Point Exception",
        16, ih_16, kernel_code_selector, kernel_flags);
    set("Alignment Check",
        17, ih_17, kernel_code_selector, kernel_flags);
    set("Machine Check",
        18, ih_18, kernel_code_selector, kernel_flags);
    set("SIMD Floating-Point Exception",
        19, ih_19, kernel_code_selector, kernel_flags);
    set("Virtualization Exception",
        20, ih_20, kernel_code_selector, kernel_flags);
    set("Reserved",
        21, ih_21, kernel_code_selector, kernel_flags);
    set("Reserved",
        22, ih_22, kernel_code_selector, kernel_flags);
    set("Reserved",
        23, ih_23, kernel_code_selector, kernel_flags);
    set("Reserved",
        24, ih_24, kernel_code_selector, kernel_flags);
    set("Reserved",
        25, ih_25, kernel_code_selector, kernel_flags);
    set("Reserved",
        26, ih_26, kernel_code_selector, kernel_flags);
    set("Reserved",
        27, ih_27, kernel_code_selector, kernel_flags);
    set("Reserved",
        28, ih_28, kernel_code_selector, kernel_flags);
    set("Reserved",
        29, ih_29, kernel_code_selector, kernel_flags);
    set("Security Exception",
        30, ih_30, kernel_code_selector, kernel_flags);
    set("Reserved",
        31, ih_31, kernel_code_selector, kernel_flags);

    set("Software Panic",
        50, ih_panic, kernel_code_selector, kernel_flags);
    set("System Call",
        100, ih_system_call, kernel_code_selector, user_flags);

    load();
}

pub fn set_kernel_handler(index: u8, handler: extern fn() void) void {
    set(index, handler, @import("segments.zig").kernel_code_selector, kernel_flags);
    load();
}

pub fn set_user_handler(index: u8, handler: extern fn() void) void {
    set(index, handler, @import("segments.zig").user_code_selector, user_flags);
    load();
}
