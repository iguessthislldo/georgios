// ============================================================================
// PS/2 Keyboard Interface
// ============================================================================

const utils = @import("utils");

const print = @import("../print.zig");

const putil = @import("util.zig");
const interrupts = @import("interrupts.zig");
const segments = @import("segments.zig");
const PS2_Scan_Code = @import("ps2_scan_codes.zig").PS2_Scan_Code;

var modifiers = utils.Key.Modifiers{};

var buffer = utils.CircularBuffer(utils.Key, 128){};

const intel8042 = struct {
    const data_port: u16 = 0x60;
    const command_status_port: u16 = 0x64;

    pub inline fn get_scan_code() ?PS2_Scan_Code {
        return utils.int_to_enum(PS2_Scan_Code, putil.in8(data_port));
    }
};

pub fn keyboard_event_occured(
        interrupt_number: u32, interrupt_stack: *const interrupts.Stack) void {
    const scan_code_maybe = intel8042.get_scan_code();
    if (scan_code_maybe == null) return;
    const scan_code = scan_code_maybe.?;
    switch (scan_code) {
        .Key_Left_Shift_Pressed => modifiers.left_shift_is_pressed = true,
        .Key_Right_Shift_Pressed => modifiers.right_shift_is_pressed = true,
        .Key_Left_Shift_Released => modifiers.left_shift_is_pressed = false,
        .Key_Right_Shift_Released => modifiers.right_shift_is_pressed = false,
        .Key_Left_Alt_Pressed => modifiers.alt_is_pressed = true,
        .Key_Left_Alt_Released => modifiers.alt_is_pressed = false,
        .Key_Left_Control_Pressed => modifiers.control_is_pressed = true,
        .Key_Left_Control_Released => modifiers.control_is_pressed = false,
        else => {
            if (scan_code.to_char()) |c| {
                buffer.push(.{.unshifted_char = c, .modifiers = modifiers});
            } else {
            }
        },
    }
}

pub fn get_text(dest: []u8) []u8 {
    putil.disable_interrupts();
    var got: usize = 0;
    while (buffer.len > 0 and got < dest.len) {
        if (buffer.pop().?.shifted_char()) |c| {
            dest[got] = c;
            got += 1;
        }
    }
    putil.enable_interrupts();
    return dest[0..got];
}

pub fn get_char() ?u8 {
    putil.disable_interrupts();
    defer putil.enable_interrupts();
    if (buffer.peek()) |key| {
        if (key.shifted_char()) |c| {
            _ = buffer.pop();
            return c;
        }
    }
    return null;
}

pub fn get_key() ?utils.Key {
    putil.disable_interrupts();
    defer putil.enable_interrupts();
    return buffer.pop();
}

pub fn init() void {
    interrupts.IrqInterruptHandler(1, keyboard_event_occured).set(
        "IRQ1: Keyboard", segments.kernel_code_selector, interrupts.kernel_flags);
    interrupts.load();
    interrupts.pic.allow_irq(1, true);
}
