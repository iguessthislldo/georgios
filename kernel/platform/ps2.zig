// ============================================================================
// PS/2 Keyboard Interface
// ============================================================================

const kutil = @import("../util.zig");
const print = @import("../print.zig");

const putil = @import("util.zig");
const interrupts = @import("interrupts.zig");
const segments = @import("segments.zig");
const PS2_Scan_Code = @import("ps2_scan_codes.zig").PS2_Scan_Code;

var right_shift_is_pressed: bool = false;
var left_shift_is_pressed: bool = false;
var alt_is_pressed: bool = false;
var control_is_pressed: bool = false;
var buffer = kutil.CircularBuffer(u8, 128){};

const intel8042 = struct {
    const data_port: u16 = 0x60;
    const command_status_port: u16 = 0x64;

    pub inline fn get_scan_code() ?PS2_Scan_Code {
        return kutil.int_to_enum(PS2_Scan_Code, putil.in8(data_port));
    }
};

pub fn keyboard_event_occured(interrupt_stack: *interrupts.InterruptStack) void {
    const scan_code_maybe = intel8042.get_scan_code();
    if (scan_code_maybe == null) return;
    const scan_code = scan_code_maybe.?;
    switch (scan_code) {
        .Key_Left_Shift_Pressed => left_shift_is_pressed = true,
        .Key_Right_Shift_Pressed => right_shift_is_pressed = true,
        .Key_Left_Shift_Released => left_shift_is_pressed = false,
        .Key_Right_Shift_Released => right_shift_is_pressed = false,
        .Key_Left_Alt_Pressed => alt_is_pressed = true,
        .Key_Left_Alt_Released => alt_is_pressed = false,
        .Key_Left_Control_Pressed => control_is_pressed = true,
        .Key_Left_Control_Released => control_is_pressed = false,
        else => {
            if (scan_code.to_char()) |c| {
                const shifted = right_shift_is_pressed or left_shift_is_pressed;
                buffer.push(if (!shifted and c >= 'A' and c <= 'Z') c + 'a' - 'A' else c);
            }
        },
    }
}

pub fn get_text(dest: []u8) []u8 {
    putil.disable_interrupts();
    var got: usize = 0;
    while (buffer.len > 0 and got < dest.len) {
        dest[got] = buffer.pop().?;
        got += 1;
    }
    putil.enable_interrupts();
    return dest[0..got];
}

pub fn get_char() ?u8 {
    putil.disable_interrupts();
    defer putil.enable_interrupts();
    return buffer.pop();
}

pub fn initialize() void {
    interrupts.IrqInterruptHandler(1, keyboard_event_occured).set(
        "IRQ1: Keyboard", segments.kernel_code_selector, interrupts.kernel_flags);
    interrupts.load();
    interrupts.pic.allow_irq(1, true);
}
