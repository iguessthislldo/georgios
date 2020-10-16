const builtin = @import("builtin");

const cga_console = @import("cga_console.zig");
const util = @import("util.zig");
const interrupts = @import("interrupts.zig");
const segments = @import("segments.zig");

const print = @import("../print.zig");
const kernel = @import("../kernel.zig");

pub fn panic(msg: []const u8, trace: ?*builtin.StackTrace) noreturn {
    asm volatile ("int $50");
    unreachable;
}

pub fn show_panic_message(
        interrupt_number: u32, interrupt_stack: *const interrupts.InterruptStack) void {
    const Color = cga_console.Color;
    cga_console.new_page();
    cga_console.set_colors(Color.Black, Color.Red);
    cga_console.fill_screen(' ');
    const ec = interrupt_stack.error_code;
    print.format(
        \\==============================<!>Kernel Panic<!>==============================
        \\The system has encountered an unrecoverable error:
        \\  Interrupt Number: {}
        \\  Error Code: {}
        \\  Message:
        , interrupt_number, ec);
    print.char(' ');

    if (!interrupts.is_exception(interrupt_number)) {
        print.string(kernel.panic_message);
    } else {
        print.string(interrupts.get_name(interrupt_number));
        if (interrupt_number == 13) {
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

        } else if (interrupt_number == 14) {
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
    );

    util.halt();
}
