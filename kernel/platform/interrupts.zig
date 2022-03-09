// Management and Base Handler Code for Interrupts
//
// TODO: More Info

const builtin = @import("std").builtin;

const kernel = @import("root").kernel;
const kutil = kernel.util;
const print = kernel.print;
const kthreading = kernel.threading;

const putil = @import("util.zig");
// TODO: Zig Bug? unable to evaluate constant expression
// const segments = @import("segments.zig");
// const kernel_code_selector = segments.kernel_code_selector;
// const user_code_selector = segments.user_code_selector;
const cga_console = @import("cga_console.zig");
const segments = @import("segments.zig");
const ps2 = @import("ps2.zig");
const system_calls = @import("system_calls.zig");

// Stack When the Interrupt is Handled ========================================
pub fn StackTemplate(comptime include_error_code: bool) type {
    return packed struct {
        const has_error_code = include_error_code;

        // Pushed by us using pusha
        edi: u32,
        esi: u32,
        ebp: u32,
        esp: u32,
        ebx: u32,
        edx: u32,
        ecx: u32,
        eax: u32,

        // Pushed by CPU
        // Pushed by some exceptions, but not others.
        error_code: if (include_error_code) u32 else void,
        eip: u32,
        cs: u32,
        eflags: u32,
    };
}
pub const Stack = StackTemplate(false);
pub const StackEc = StackTemplate(true);

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

// TODO: Bochs error for interrupt 39 is missing default error messeage, figure
// out why.
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
        name: []const u8, index: u8, handler: fn() void,
        selector: u16, flags: u8) void {
    const offset: u32 = @ptrToInt(handler);
    names[index] = name;
    print.debug_format(
        "   - [{}]: \"{}\"\n" ++
        "     - selector: {:x} address: {:a} flags: {:x}\n", .{
        index, name, selector, offset,  flags});
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

pub fn PanicMessage(comptime StackType: type) type {
    return struct {
        pub fn show(interrupt_number: u32, interrupt_stack: *const StackType) void {
            const Color = cga_console.Color;
            cga_console.reset();
            cga_console.show_cursor(false);
            cga_console.set_colors(Color.Black, Color.Red);
            cga_console.fill_screen(' ');
            const has_ec = StackType.has_error_code;
            const ec = interrupt_stack.error_code;
            print.format(
                \\==============================<!>Kernel Panic<!>==============================
                \\The system has encountered an unrecoverable error:
                \\  Interrupt Number: {}
                \\
                , .{interrupt_number});
            if (has_ec) {
                print.format("  Error Code: {}\n", .{ec});
            }
            print.string("  Message: ");
            if (!is_exception(interrupt_number)) {
                print.string(kernel.panic_message);
            } else {
                print.string(get_name(interrupt_number));
                if (has_ec and interrupt_number == 13) {
                    // Explain General Protection Fault Cause
                    const which_table = @intCast(u2, (ec >> 1) & 3);
                    const table_index = (ec >> 3) & 8191;
                    print.format("{} Caused By {}[{}]", .{
                        if ((ec & 1) == 1)
                            @as([]const u8, " Externally") else @as([]const u8, ""),
                        @as([]const u8, switch (which_table) {
                            0 => "GDT",
                            1 => "IDT",
                            2 => "LDT",
                            3 => "IDT",
                        }), table_index});
                    if (which_table == 0) {
                        // Print Selector if GDT
                        print.format(" ({})", .{segments.get_name(table_index)});
                    } else if ((which_table & 1) == 1) {
                        // Print Interrupt if IDT
                        print.format(" ({})", .{get_name(table_index)});
                    }

                } else if (has_ec and interrupt_number == 14) {
                    // Explain Page Fault Cause
                    const what = if ((ec & 1) > 0)
                        @as([]const u8, "Page Protection Violation") else
                        @as([]const u8, "Missing Page");
                    const reserved = if ((ec & 8) > 0)
                        @as([]const u8, " (Reserved bits set in directory entry)") else
                        @as([]const u8, "");
                    const when =
                        if ((ec & 16) > 0)
                            @as([]const u8, "Fetching an Instruction From")
                        else
                            (if ((ec & 2) > 0) @as([]const u8, "Writing to") else
                            @as([]const u8, "Reading From"));
                    const user =
                        if ((ec & 4) > 0) @as([]const u8, "User") else
                            @as([]const u8, "Non-User");
                    print.format("\n    {}{} While {} {:a} while in {} Ring", .{
                        what, reserved, when, putil.cr2(), user});
                    // TODO: Zig Compiler Assertion
                    // print.format("\n    {}{} While {} {:a} while in {} Ring", .{
                    //     if ((ec & 1) > 0)
                    //         @as([]const u8, "Page Protection Violation") else
                    //         @as([]const u8, "Missing Page"),
                    //     if ((ec & 8) > 0)
                    //         @as([]const u8, " (Reserved bits set in directory entry)") else
                    //         @as([]const u8, ""),
                    //     if ((ec & 16) > 0)
                    //         @as([]const u8, "Fetching an Instruction From")
                    //     else
                    //         (if ((ec & 2) > 0) @as([]const u8, "Writing to") else
                    //         @as([]const u8, "Reading From")),
                    //     putil.cr2(),
                    //     if ((ec & 4) > 0) @as([]const u8, "User") else
                    //         @as([]const u8, "Non-User")});
                }
            }

            print.format(
                \\
                \\
                \\--Registers-------------------------------------------------------------------
                \\    EIP: {:a}
                \\    EFLAGS: {:x}
                \\    EAX: {:x}
                \\    ECX: {:x}
                \\    EDX: {:x}
                \\    EBX: {:x}
                \\    ESP: {:a}
                \\    EBP: {:a}
                \\    ESI: {:x}
                \\    EDI: {:x}
                \\    CS: {:x} ({})
                , .{
                interrupt_stack.eip,
                interrupt_stack.eflags,
                interrupt_stack.eax,
                interrupt_stack.ecx,
                interrupt_stack.edx,
                interrupt_stack.ebx,
                interrupt_stack.esp,
                interrupt_stack.ebp,
                interrupt_stack.esi,
                interrupt_stack.edi,
                interrupt_stack.cs,
                segments.get_name(interrupt_stack.cs / 8),
            });

            putil.done();
        }
    };
}

fn BaseInterruptHandler(
        comptime i: u32, comptime StackType: type, comptime irq: bool,
        impl: fn(u32, *const StackType) void) type {
    return struct {
        const index: u8 = i;
        const irq_number: u32 = if (irq) i - pic.irq_0_7_interrupt_offset else 0;

        fn inner_handler(interrupt_stack: *const StackType) void {
            const spurious =
                if (irq_number == 7 or irq_number == 15)
                    pic.is_spurious_irq(irq_number)
                else
                    false;
            if (irq) {
                if (!spurious) {
                    impl(irq_number, interrupt_stack);
                }
                pic.end_of_interrupt(irq_number, spurious);
            } else if (!spurious) {
                impl(@as(u32, i), interrupt_stack);
            }
        }

        pub fn handler() callconv(.Naked) noreturn {
            asm volatile ("cli");

            // Push EAX, ECX, EDX, EBX, original ESP, EBP, ESI, and EDI
            asm volatile ("pushal");

            inner_handler(asm volatile ("mov %%esp, %[interrupt_stack]"
                : [interrupt_stack] "={eax}" (-> *const StackType)));

            asm volatile ("popal"); // Restore Registers
            if (StackType.has_error_code) {
                asm volatile ("addl $4, %%esp"); // Pop Error Code
            }
            asm volatile ("iret");
            unreachable;
        }

        pub fn get() fn() void {
            return @ptrCast(fn() void, handler);
        }

        pub fn set(name: []const u8, selector: u16, flags: u8) void {
            set_entry(name, index, @ptrCast(fn() void, handler), selector, flags);
        }
    };
}

fn HardwareErrorInterruptHandler(
        comptime i: u32, comptime error_code: bool) type {
    const StackType = StackTemplate(error_code);
    return BaseInterruptHandler(
        i, StackType, false, PanicMessage(StackType).show);
}

pub fn IrqInterruptHandler(
        comptime irq_number: u32, impl: fn(u32, *const Stack) void) type {
    return BaseInterruptHandler(irq_number + pic.irq_0_7_interrupt_offset,
        Stack, true, impl);
}

fn InterruptHandler(comptime i: u32, impl: fn(u32, *const Stack) void) type {
    return BaseInterruptHandler(i, Stack, false, impl);
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

    const irq_0_7_command_port: u16 = 0x20;
    const irq_0_7_data_port: u16 = 0x21;
    const irq_8_15_command_port: u16 = 0xA0;
    const irq_8_15_data_port: u16 = 0xA1;

    const read_irr_command: u8 = 0x0a;
    const read_isr_command: u8 = 0x0b;
    const init_command: u8 = 0x11;
    const reset_command: u8 = 0x20;

    fn busywork() callconv(.Inline) void {
        asm volatile (
            \\add %%ch, %%bl
            \\add %%ch, %%bl
        );
    }

    fn irq_mask(irq: u8) callconv(.Inline) u8 {
        var offset = irq;
        if (irq >= 8) {
            offset -= 8;
        }
        return @as(u8, 1) << @intCast(u3, offset);
    }

    pub fn is_spurious_irq(irq: u8) bool {
        var port = irq_0_7_command_port;
        if (irq >= 8) {
            port = irq_8_15_command_port;
        }
        putil.out8(port, read_isr_command);
        const rv = putil.in8(port) & irq_mask(irq) == 0;
        return rv;
    }

    pub fn end_of_interrupt(irq: u8, spurious: bool) void {
        const chained = irq >= 8;
        if (chained and !spurious) {
            putil.out8(irq_8_15_command_port, reset_command);
        }
        if (!spurious or (chained and spurious)) {
            putil.out8(irq_0_7_command_port, reset_command);
        }
        busywork();
    }

    pub fn allow_irq(irq: u8, enabled: bool) void {
        var port = irq_0_7_data_port;
        if (irq >= 8) {
            port = irq_8_15_data_port;
        }
        putil.out8(port, putil.in8(port) & ~irq_mask(irq));
        busywork();
    }

    pub fn init() void {
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

pub var in_tick = false;

fn tick(irq_number: u32, interrupt_stack: *const Stack) void {
    in_tick = true;
    if (kthreading.debug) print.char('!');
    kernel.threading_mgr.yield();
    in_tick = false;
}

pub fn init() void {
    table_pointer.limit = @sizeOf(Entry) * table.len;
    table_pointer.base = @ptrToInt(&table);
    // TODO: See top of file
    const kernel_code_selector = @import("segments.zig").kernel_code_selector;

    print.debug_string(" - Filling the Interrupt Descriptor Table (IDT)\n");

    const debug_print_value = print.debug_print;
    print.debug_print = false; // Too many lines
    comptime var interrupt_number = 0;
    comptime var exceptions_index = 0;
    @setEvalBranchQuota(2000);
    inline while (interrupt_number < 150) {
        if (exceptions_index < exceptions.len and
                exceptions[exceptions_index].index == interrupt_number) {
            exceptions_index += 1;
        } else {
            HardwareErrorInterruptHandler(interrupt_number, false).set(
                "Unknown Interrupt", kernel_code_selector, kernel_flags);
        }
        interrupt_number += 1;
    }
    print.debug_print = debug_print_value;

    inline for (exceptions) |ex| {
        HardwareErrorInterruptHandler(ex.index, ex.error_code).set(
            ex.name, kernel_code_selector, kernel_flags);
    }

    InterruptHandler(50, PanicMessage(Stack).show).set(
        "Software Panic", kernel_code_selector, kernel_flags);

    InterruptHandler(system_calls.interrupt_number, system_calls.handle).set(
        "System Call", kernel_code_selector, user_flags);

    IrqInterruptHandler(0, tick).set(
        "IRQ0: Timer", kernel_code_selector, kernel_flags);

    load();

    pic.init();
}

pub fn set_kernel_handler(index: u8, handler: fn() void) void {
    set(index, handler, @import("segments.zig").kernel_code_selector, kernel_flags);
    load();
}

pub fn set_user_handler(index: u8, handler: fn() void) void {
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
