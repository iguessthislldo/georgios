// ============================================================================
// PS/2 Keyboard Interface
// ============================================================================

const build_options = @import("build_options");

const utils = @import("utils");
const georgios = @import("georgios");
const keyboard = georgios.keyboard;
const Key = keyboard.Key;
const Event = keyboard.Event;

const kernel = @import("root").kernel;
const print = kernel.print;
const key_to_char = kernel.keys.key_to_char;

const putil = @import("util.zig");
const interrupts = @import("interrupts.zig");
const segments = @import("segments.zig");
const scan_codes = @import("ps2_scan_codes.zig");

var modifiers = keyboard.Modifiers{};

var buffer = utils.CircularBuffer(Event, 128, .DiscardNewest){};

const intel8042 = struct {
    const data_port: u16 = 0x60;
    const command_status_port: u16 = 0x64;

    pub fn get_kb_byte() callconv(.Inline) u8 {
        return putil.in8(data_port);
    }
};

/// Number of bytes into the current pattern.
var byte_count: u8 = 0;

const Pattern = enum {
    TwoBytePrintScreen,
    PrintScreenPressed,
    PrintScreenReleased,
    Pause,
};

/// Current multibyte patterns that are possible.
var pattern: Pattern = undefined;

pub fn keyboard_event_occured(
        interrupt_number: u32, interrupt_stack: *const interrupts.Stack) void {
    var event: ?Event = null;
    const byte = intel8042.get_kb_byte();
    // print.format("[{:x}]", .{byte});
    var reset = false;
    switch (byte_count) {
        0 => switch (byte) {
            // Towards Two Bytes or PrintScreen
            0xe0 => pattern = .TwoBytePrintScreen,

            // Towards Pause
            0xe1 => pattern = .Pause,

            // Reached One Byte
            else => {
                const entry = scan_codes.one_byte[byte];
                if (entry.key) |key| {
                    event = Event.new(key, entry.shifted_key, entry.kind.?, &modifiers);
                }
                reset = true;
            },
        },

        1 => switch (pattern) {
            .TwoBytePrintScreen => switch (byte) {
                // Towards PrintScreen Pressed
                0x2a => pattern = .PrintScreenPressed,

                // Towards PrintScreen Released
                0xb7 => pattern = .PrintScreenReleased,

                // Reached Two Bytes
                else => {
                    const entry = scan_codes.two_byte[byte];
                    if (entry.key) |key| {
                        event = Event.new(key, entry.shifted_key, entry.kind.?, &modifiers);
                    }
                    reset = true;
                },
            },

            // Towards Pause
            .Pause => reset = byte != 0x1d,

            else => reset = true,
        },

        2 => switch (pattern) {
            // Towards PrintScreen Pressed and Released
            .PrintScreenPressed, .PrintScreenReleased => reset = byte != 0xe0,

            // Towards Pause
            .Pause => reset = byte != 0x45,

            else => reset = true,
        },

        3 => switch (pattern) {
            .PrintScreenPressed => {
                if (byte == 0x37) {
                    // Reached PrintScreen Pressed
                    event = Event.new(.Key_PrintScreen, null, .Pressed, &modifiers);
                }
                reset = true;
            },

            .PrintScreenReleased => {
                if (byte == 0xaa) {
                    // Reached PrintScreen Released
                    event = Event.new(.Key_PrintScreen, null, .Released, &modifiers);
                }
                reset = true;
            },


            // Towards Pause
            .Pause => reset = byte != 0xe1,

            else => reset = true,
        },

        4 => switch (pattern) {
            // Towards Pause
            .Pause => reset = byte != 0x9d,

            else => reset = true,
        },

        5 => switch (pattern) {
            // Towards Pause
            .Pause => {
                if (byte == 0xc5) {
                    // Reached Pause
                    event = Event.new(.Key_Pause, null, .Hit, &modifiers);
                }
                reset = true;
            },

            else => reset = true,
        },

        else => reset = true,
    }

    if (reset) {
        byte_count = 0;
    } else {
        byte_count += 1;
    }

    if (event != null) {
        const e = &event.?;
        modifiers.update(e);
        // print.format("<{}: {}>", .{@tagName(e.key), @tagName(e.kind)});
        if (e.kind == .Pressed) {
            if (key_to_char(e.key)) |c| {
                e.char = c;
            }
        }
        buffer.push(e.*);
        kernel.threading_mgr.keyboard_event_occured();
    }
}

pub fn get_key() ?Event {
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

pub fn anykey() void {
    if (build_options.wait_for_anykey) {
        while (true) {
            if (get_key()) |key| {
                if (key.kind == .Released) {
                    break;
                }
            }
        }
    }
}
