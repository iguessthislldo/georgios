const builtin = @import("builtin");

const kutil = @import("../util.zig");
const print = @import("../print.zig");

const putil = @import("util.zig");
// TODO: Zig Bug? unable to evaluate constant expression
// const segments = @import("segments.zig");
// const kernel_code_selector = segments.kernel_code_selector;
// const user_code_selector = segments.user_code_selector;
const panic = @import("panic.zig");

pub const InterruptStack = packed struct {
    // Pushed by us using pusha
    edi: u32,
    esi: u32,
    ebp: u32,
    esp: u32,
    ebx: u32,
    edx: u32,
    ecx: u32,
    eax: u32,
    // Set to zero if the CPU didn't push one
    error_code: u32,
    // Pushed by CPU
    eip: u32,
    cs: u32,
    eflags: u32,
};

// System Calls ==============================================================

const system_call_interrupt_number: u8 = 100;
fn handle_system_call(interrupt_number: u32, interrupt_stack: *InterruptStack) void {
    const call_number = interrupt_stack.eax;
    const arg1 = interrupt_stack.ebx;
    switch (call_number) {
        0 => print.string(@intToPtr(*[]const u8, arg1).*),
        1 => {
            const ps2 = @import("ps2.zig");
            while (true) {
                if (ps2.get_char()) |c| {
                    @intToPtr(*u8, arg1).* = c;
                    break;
                }
                putil.wait_milliseconds(100);
            }
        },
        else => @panic("Invalid System Call"),
    }
}

// Interrupt Descriptor Table ================================================

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

const TablePointer = packed struct {
    limit: u16,
    base: u32,
};
var table_pointer: TablePointer = undefined;

pub fn load() void {
    asm volatile ("lidtl (%[p])" : : [p] "{ax}" (&table_pointer));
}

fn set_entry(
        name: []const u8, index: u8, handler: extern fn() void,
        selector: u16, flags: u8) void {
    const offset: u32 = @ptrToInt(handler);
    names[index] = name;
    print.debug_format(
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
pub const kernel_flags: u8 = 0x8e;
pub const user_flags: u8 = kernel_flags | (3 << 5);

// Interrupt Handler Generation ==============================================

fn BaseInterruptHandler(
        comptime i: u32, comptime error_code: bool, comptime irq: bool,
        impl: fn(u32, *InterruptStack) void) type {
    return struct {
        const index: u8 = i;

        fn inner_handler(real_interrupt_stack: u32) void {
            // Copy Interrupt Stack And Insert Dummy Error Code If Needed
            const real_interrupt_stack_bytes = kutil.to_bytes(
                @intToPtr(*InterruptStack, real_interrupt_stack));
            var interrupt_stack: InterruptStack = undefined;
            const interrupt_stack_bytes = kutil.to_bytes(&interrupt_stack);
            if (error_code) {
                _ = kutil.memory_copy_truncate(
                    interrupt_stack_bytes, real_interrupt_stack_bytes);
            } else {
                const error_code_offset = @byteOffsetOf(InterruptStack, "error_code");
                _ = kutil.memory_copy_truncate(
                    interrupt_stack_bytes, real_interrupt_stack_bytes[0..error_code_offset]);
                interrupt_stack.error_code = 0;
                _ = kutil.memory_copy_truncate(
                    interrupt_stack_bytes[error_code_offset + @sizeOf(u32)..],
                    real_interrupt_stack_bytes[error_code_offset..]);
            }

            // Call the Handler Implementation
            if (irq) {
                const irq_number = u32(i - pic.irq_0_7_interrupt_offset);
                pic.silence_irq(irq_number);
                impl(irq_number, &interrupt_stack);
            } else {
                impl(u32(i), &interrupt_stack);
            }
        }

        pub nakedcc fn handler() noreturn {
            asm volatile ("cli");
            // Push EAX, ECX, EDX, EBX, original ESP, EBP, ESI, and EDI
            asm volatile ("pushal");

            inner_handler(asm volatile ("mov %%esp, %[interrupt_stack]"
                : [interrupt_stack] "={eax}" (-> u32)));

            asm volatile ("popal"); // Restore Registers
            if (error_code) asm volatile ("addl $4, %%esp"); // Pop Error Code
            asm volatile ("iret");
            unreachable;
        }

        pub fn get() extern fn() void {
            return @ptrCast(extern fn() void, handler);
        }

        pub fn set(name: []const u8, selector: u16, flags: u8) void {
            set_entry(name, index, @ptrCast(extern fn() void, handler), selector, flags);
        }
    };
}

fn HardwareErrorInterruptHandler(
        comptime i: u32, comptime error_code: bool) type {
    return BaseInterruptHandler(i, error_code, false, panic.show_panic_message);
}

pub fn IrqInterruptHandler(
        comptime irq_number: u32, impl: fn(u32, *InterruptStack) void) type {
    return BaseInterruptHandler(
        irq_number + pic.irq_0_7_interrupt_offset, false, true, impl);
}

// CPU Exception Interrupts ==================================================

const Exception = struct {
    name: []const u8,
    index: u32,
    error_code: bool,
};

const exceptions = [_]Exception {
  Exception{.name = "Divide by Zero Fault", .index = 0, .error_code = false},
  Exception{.name = "Debug Trap", .index = 1, .error_code = false},
  Exception{.name = "Nonmaskable Interrupt", .index = 2, .error_code = false},
  Exception{.name = "Breakpoint Trap", .index = 3, .error_code = false},
  Exception{.name = "Overflow Trap", .index = 4, .error_code = false},
  Exception{.name = "Bounds Fault", .index = 5, .error_code = false},
  Exception{.name = "Invalid Opcode", .index = 6, .error_code = false},
  Exception{.name = "Device Not Available", .index = 7, .error_code = false},
  Exception{.name = "Double Fault", .index = 8, .error_code = true},
  Exception{.name = "Coprocessor Segment Overrun", .index = 9, .error_code = false},
  Exception{.name = "Invalid TSS", .index = 10, .error_code = true},
  Exception{.name = "Segment Not Present", .index = 11, .error_code = true},
  Exception{.name = "Stack-Segment Fault", .index = 12, .error_code = true},
  Exception{.name = "General Protection Fault", .index = 13, .error_code = true},
  Exception{.name = "Page Fault", .index = 14, .error_code = true},
  Exception{.name = "x87 Floating-Point Exception", .index = 16, .error_code = false},
  Exception{.name = "Alignment Check", .index = 17, .error_code = true},
  Exception{.name = "Machine Check", .index = 18, .error_code = false},
  Exception{.name = "SIMD Floating-Point Exception", .index = 19, .error_code = false},
  Exception{.name = "Virtualization Exception", .index = 20, .error_code = false},
  Exception{.name = "Security Exception", .index = 30, .error_code = true},
};

// 8259 Programmable Interrupt Controller (PIC) ==============================

pub const pic = struct {
    const irq_0_7_interrupt_offset: u8 = 32;
    const irq_8_15_interrupt_offset: u8 = irq_0_7_interrupt_offset + 8;

    const channel_port: u16 = 0x40;
    const mode_port: u16 = 0x43;
    const irq_0_7_command_port: u16 = 0x20;
    const irq_0_7_data_port: u16 = 0x21;
    const irq_8_15_command_port: u16 = 0xA0;
    const irq_8_15_data_port: u16 = 0xA1;

    const init_command: u8 = 0x11;
    const reset_command: u8 = 0x20;

    fn busywork() void {
        asm volatile (
            \\add %%ch, %%bl
            \\add %%ch, %%bl
        );
    }

    pub fn silence_irq(irq: u8) void {
        if (irq >= 8) putil.out8(irq_8_15_data_port, reset_command);
        putil.out8(irq_0_7_command_port, reset_command);
        busywork();
    }

    pub fn allow_irq(irq: u8, enabled: bool) void {
        var offset = irq;
        var port = irq_0_7_data_port;
        if (irq >= 8) {
            offset -= 8;
            port = irq_8_15_data_port;
        }
        putil.out8(port, putil.in8(port) & ~(u8(1) << @intCast(u3, offset)));
        busywork();
    }

    pub fn initialize() void {
        // Start Initialization of PICs
        putil.out8(irq_0_7_command_port, init_command);
        busywork();
        putil.out8(irq_8_15_command_port, init_command);
        busywork();

        // Set Interrupt Number Offsets for IRQs
        putil.out8(irq_0_7_data_port, irq_0_7_interrupt_offset);
        busywork();
        putil.out8(irq_8_15_data_port, irq_8_15_interrupt_offset);
        busywork();

        // Tell PICs About Each Other
        putil.out8(irq_0_7_data_port, 4);
        busywork();
        putil.out8(irq_8_15_data_port, 2);
        busywork();

        // Set Mode of PICs
        putil.out8(irq_0_7_data_port, 1);
        busywork();
        putil.out8(irq_8_15_data_port, 1);
        busywork();

        // Disable All IRQs for Now
        putil.out8(irq_0_7_data_port, 0xff);
        busywork();
        putil.out8(irq_8_15_data_port, 0xff);
        busywork();

        // Enable Interrupts
        putil.enable_interrupts();
    }
};

// Public Interface ==========================================================

pub fn initialize() void {
    table_pointer.limit = @sizeOf(Entry) * table.len;
    table_pointer.base = @ptrToInt(&table);
    // TODO: See top of file
    const kernel_code_selector = @import("segments.zig").kernel_code_selector;

    print.debug_string(" - Filling the Interrupt Descriptor Table (IDT)\n");

    const debug_print_value = print.debug_print;
    print.debug_print = false; // Too many lines
    comptime var index = 0;
    inline while (index < 256) {
        HardwareErrorInterruptHandler(index, false).set(
            "Unknown Interrupt", kernel_code_selector, kernel_flags);
        index += 1;
    }
    print.debug_print = debug_print_value;

    inline for (exceptions) |ex| {
        HardwareErrorInterruptHandler(ex.index, ex.error_code).set(
            ex.name, kernel_code_selector, kernel_flags);
    }

    BaseInterruptHandler(50, false, false, panic.show_panic_message).set(
        "Software Panic", kernel_code_selector, kernel_flags);

    BaseInterruptHandler(
        system_call_interrupt_number, false, false, handle_system_call).set(
            "System Call", kernel_code_selector, user_flags);

    load();

    pic.initialize();
}

pub fn set_kernel_handler(index: u8, handler: extern fn() void) void {
    set(index, handler, @import("segments.zig").kernel_code_selector, kernel_flags);
    load();
}

pub fn set_user_handler(index: u8, handler: extern fn() void) void {
    set(index, handler, @import("segments.zig").user_code_selector, user_flags);
    load();
}

pub fn get_name(index: u32) []const u8 {
    return if (index < names.len) names[index] else
        invalid_index ++ " and out of range";
}

pub fn is_exception(index: u32) bool {
    return index <= exceptions.len;
}
