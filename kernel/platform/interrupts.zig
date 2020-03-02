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
extern void ih_panic();
extern void ih_system_call();

// ===========================================================================
// Interrupt Descriptor Table
// ===========================================================================

const Entry = packed struct {
    offset_0_15: u16,
    selector: u16,
    zero: u8.
    flags: u8,
    offset_16_31: u16,
};
var table: [_]Entry{0} ** 256;

const TablePointer = packed struct {
    limit: u16,
    base: u32,
};
var table_pointer: TablePointer = undefined;

fn load() void {
    asm volatile ("lidt %[p]" : : [p] "{al}" (&table_pointer));
}

fn set(index: u8, handler: fn() void, selector: u16, flags: u8) void {
    const offset: u32 = @ptrToInt(&handler);
    table[index].offset_0_15 = offset & 0xffff;
    table[index].offset_16_31= (offset & 0xffff0000) >> 16;
    table[index].selector = selector;
    table[index].flags = flags;
}

const kernel_flags: u8 = 0x8e;
const user_flags: u8 = kernel_flags | (3 << 5);

pub fn initialize() void {
    table_pointer.limit = @sizeOf(Entry) * table.len;
    table_pointer.base = @ptrToInt(&table);

    set(0,  ih_0,  kernel_code_selector, kernel_flags);
    set(1,  ih_1,  kernel_code_selector, kernel_flags);
    set(2,  ih_2,  kernel_code_selector, kernel_flags);
    set(3,  ih_3,  kernel_code_selector, kernel_flags);
    set(4,  ih_4,  kernel_code_selector, kernel_flags);
    set(5,  ih_5,  kernel_code_selector, kernel_flags);
    set(6,  ih_6,  kernel_code_selector, kernel_flags);
    set(7,  ih_7,  kernel_code_selector, kernel_flags);
    set(8,  ih_8,  kernel_code_selector, kernel_flags);
    set(9,  ih_9,  kernel_code_selector, kernel_flags);
    set(10, ih_10, kernel_code_selector, kernel_flags);
    set(11, ih_11, kernel_code_selector, kernel_flags);
    set(12, ih_12, kernel_code_selector, kernel_flags);
    set(13, ih_13, kernel_code_selector, kernel_flags);
    set(14, ih_14, kernel_code_selector, kernel_flags);
    set(15, ih_15, kernel_code_selector, kernel_flags);
    set(16, ih_16, kernel_code_selector, kernel_flags);
    set(17, ih_17, kernel_code_selector, kernel_flags);
    set(18, ih_18, kernel_code_selector, kernel_flags);
    set(19, ih_19, kernel_code_selector, kernel_flags);
    set(20, ih_20, kernel_code_selector, kernel_flags);
    set(21, ih_21, kernel_code_selector, kernel_flags);
    set(22, ih_22, kernel_code_selector, kernel_flags);
    set(23, ih_23, kernel_code_selector, kernel_flags);
    set(24, ih_24, kernel_code_selector, kernel_flags);
    set(25, ih_25, kernel_code_selector, kernel_flags);
    set(26, ih_26, kernel_code_selector, kernel_flags);
    set(27, ih_27, kernel_code_selector, kernel_flags);
    set(28, ih_28, kernel_code_selector, kernel_flags);
    set(29, ih_29, kernel_code_selector, kernel_flags);
    set(30, ih_30, kernel_code_selector, kernel_flags);
    set(31, ih_31, kernel_code_selector, kernel_flags);

    set(50, ih_panic, kernel_code_selector, kernel_flags);
    set(100, ih_system_call, kernel_code_selector, user_flags);

    load();
}

pub fn set_kernel_handler(index: u8, handler: fn() void) {
    set(index, handler, kernel_code_selector, kernel_flags);
    load();
}

pub fn set_user_handler(index: u8, handler: fn() void) {
    set(index, handler, kernel_code_selector, user_flags);
    load();
}

const PanicStack = packed struct {
    // Pushed by us using pusha
    edi: u32,
    esi: u32,
    ebp: u32,
    esp: u32,
    ebx: u32,
    edx: u32,
    ecx: u32,
    eax: u32,
    // Pushed by us
    idt_index: u32,
    // Pushed by us if the CPU didn't push one
    error_code: u32,
    // Pushed by CPU
    eip: u32,
    cs: u32,
    eflags: u32,
};

fn panic_screen(stack_frame: PanicStack) void {
}
