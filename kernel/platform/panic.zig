const builtin = @import("builtin");

const cga_console = @import("cga_console.zig");
const util = @import("util.zig");
const interrupts = @import("interrupts.zig");
const segments = @import("segments.zig");

const print = @import("../print.zig");
const kernel = @import("../kernel.zig");

pub fn panic(msg: []const u8, trace: ?*builtin.StackTrace) noreturn {
    // The push $0 is a left over from being able to set the error code for the
    // C panic.
    // Also see handler code for this in ./interrupts.zig.
    // TODO: Remove or Reuse?
    asm volatile ("pushl $0\n\tint $50");
    unreachable;
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

pub export var panic_stack: *PanicStack = undefined;

pub export fn show_panic_message() void {
    const Color = cga_console.Color;
    cga_console.new_page();
    cga_console.set_colors(Color.Black, Color.Red);
    cga_console.fill_screen(' ');
    const ec = panic_stack.error_code;
    const index = panic_stack.idt_index;
    print.format(
        \\==============================<!>Kernel Panic<!>==============================
        \\The system has encountered an unrecoverable error:
        \\  Interrupt Number: {}
        \\  Error Code: {}
        \\  Message:
        , index, ec);
    print.char(' ');

    if (!interrupts.is_exception(index)) {
        print.string(kernel.panic_message);
    } else {
        print.string(interrupts.get_name(index));
        if (index == 13) {
            // Explain General Protection Fault Cause
            const table = @intCast(u2, (ec >> 1) & 3);
            const table_index = (ec >> 3) & 8191;
            print.format("{} Caused By {}[{}]",
                if ((ec & 1) == 1) " Externally" else "",
                switch (table) {
                    0 => "GDT",
                    1 => "IDT",
                    2 => "LDT",
                    3 => "IDT",
                }, table_index);
            if (table == 0) {
                // Print Selector if GDT
                print.format(" ({})", segments.get_name(table_index));
            } else if ((table & 1) == 1) {
                // Print Interrupt if IDT
                print.format(" ({})", interrupts.get_name(table_index));
            }

        } else if (index == 14) {
            // Explain Page Fault Cause
            print.format("\n    {}{} While {} {:a} while in {} Ring",
                if ((ec & 1) > 0) "Page Protection Violation" else "Missing Page",
                if ((ec & 8) > 0) " (Reserved bits set in directory entry)" else "",
                if ((ec & 16) > 0)
                    "Fetching an Instruction From"
                else
                    (if ((ec & 2) > 0) "Writing to" else "Reading From"),
                util.cr2(),
                if ((ec & 4) > 0) "User" else "Non-User");
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
        ,
        panic_stack.eip,
        panic_stack.eflags,
        panic_stack.eax,
        panic_stack.ecx,
        panic_stack.edx,
        panic_stack.ebx,
        panic_stack.esp,
        panic_stack.ebp,
        panic_stack.esi,
        panic_stack.edi,
        panic_stack.cs,
        segments.get_name(panic_stack.cs / 8),
    );

    util.halt();
}
