// ============================================================================
// PS/2 Driver for Mouse and Keyboard
// Interacts through the Intel 8042 controller.
//
// For reference:
//   https://wiki.osdev.org/%228042%22_PS/2_Controller
//   https://wiki.osdev.org/PS/2_Keyboard
//   https://isdaman.com/alsos/hardware/mouse/ps2interface.htm
//   https://wiki.osdev.org/PS/2_Mouse
// ============================================================================

const build_options = @import("build_options");

const utils = @import("utils");
const georgios = @import("georgios");
const keyboard = georgios.keyboard;
const Key = keyboard.Key;
const KeyboardEvent = keyboard.Event;
const MouseEvent = georgios.MouseEvent;

const kernel = @import("root").kernel;
const print = kernel.print;
const key_to_char = kernel.keys.key_to_char;

const putil = @import("util.zig");
const interrupts = @import("interrupts.zig");
const segments = @import("segments.zig");
const scan_codes = @import("ps2_scan_codes.zig");

const Error = error {
    Ps2ResetFailed,
    Ps2DeviceIssue,
};

var keyboard_initialized = false;
var keyboard_modifiers = keyboard.Modifiers{};
var keyboard_buffer = utils.CircularBuffer(KeyboardEvent, 128, .DiscardNewest){};

var mouse_initialized = false;
var mouse_buffer = utils.CircularBuffer(MouseEvent, 256, .DiscardNewest){};

const controller = struct {
    const data_port: u16 = 0x60;
    const command_status_port: u16 = 0x64;
    const ack: u8 = 0xfa;

    const DeviceKind = enum {
        Unknown,
        Keyboard,
        Mouse,
    };

    var port1_device: ?DeviceKind = null;
    var port2_device: ?DeviceKind = null;

    fn port1_is_keyboard() bool {
        return port1_device == DeviceKind.Keyboard;
    }

    fn port2_is_mouse() bool {
        return port2_device == DeviceKind.Mouse;
    }

    const Status = packed struct {
        const Dest = enum(u1) {
            Device = 0,
            Controller = 1,
        };

        has_data: bool,
        not_ready_for_write: bool,
        system_flag: bool,
        write_dest: Dest,
        unknown: u2,
        timeout_error: bool,
        parity_error: bool,
    };

    fn read_status() Status {
        return @bitCast(Status, putil.in8(command_status_port));
    }

    fn read_data_with_timeout(timeout: u16) ?u8 {
        var n: usize = 0;
        while (true) {
            if (read_status().has_data) {
                const byte = putil.in8(data_port);
                // print.format("read_data_with_timeout: {:x}\n", .{byte});
                return byte;
            }
            if (timeout > 0) {
                n += 1;
                if (n >= timeout) break;
            }
        }
        // print.string("read_data_with_timeout: null\n");
        return null;
    }

    fn read_data() u8 {
        return read_data_with_timeout(0).?;
    }

    fn read_data_as(comptime Type: type, timeout: u16) Error!Type {
        var status: [@sizeOf(Type)]u8 = undefined;
        for (status) |*byte| {
            byte.* = read_data_with_timeout(timeout) orelse {
                return Error.Ps2DeviceIssue;
            };
        }

        return @bitCast(Type, status);
    }

    fn write(port: u16, value: u8) void {
        while (read_status().not_ready_for_write) {
        }
        return putil.out8(port, value);
    }

    fn write_data(value: u8) void {
        write(data_port, value);
    }

    const HasResponse = enum {
        NoRes,
        HasRes,
    };

    fn command(cmd: u8, arg: ?u8, has_res: HasResponse) ?u8 {
        write(command_status_port, cmd);
        if (arg) |arg_byte| {
            write_data(arg_byte);
        }
        return if (has_res == .HasRes) read_data() else null;
    }

    const Config = packed struct {
        port1_interrupt_enabled: bool,
        port2_interrupt_enabled: bool,
        system_flag: bool,
        zero1: u1 = 0,
        port1_check: bool,
        port2_check: bool,
        port1_translation: bool,
        zero2: u1 = 0,
    };

    fn read_config() Config {
        return @bitCast(Config, command(0x20, null, .HasRes).?);
    }

    fn write_config(config: Config) void {
        _ = command(0x60, @bitCast(u8, config), .NoRes);
    }

    const Port = enum(u2) {
        Port1 = 0,
        Port2 = 1,
    };

    fn enable_port(port: Port, enabled: bool) void {
        const cmds = [_]u8{0xad, 0xae, 0xa7, 0xa8};
        _ = command(cmds[(@enumToInt(port) << 1) | @boolToInt(enabled)], null, .NoRes);
    }

    fn device_command(port: Port, cmd: u8) u8 {
        if (port == .Port1) {
            write_data(cmd);
        } else {
            _ = command(0xd4, cmd, .NoRes);
        }
        return read_data();
    }

    const MouseStatus = packed struct {
        const Scaling = enum(u1) {
            OneToOne = 0,
            TwoToOne = 1,
        };

        const Mode = enum(u1) {
            Stream = 0,
            Remote = 1,
        };

        rmb_pressed: bool,
        mmb_pressed: bool,
        lmb_pressed: bool,
        zero1: u1 = 0,
        scaling: Scaling,
        data_enabled: bool,
        mode: Mode,
        zero2: u1 = 0,
        resolution: u8,
        sample_rate: u8,
    };

    fn get_mouse_status(port: Port) Error!MouseStatus {
        const ack_res = device_command(port, 0xe9);
        if (ack_res != ack) {
            print.format("WARNING: get_mouse_status: PS/2 device on {} replied {} for ack\n",
                .{port, ack_res});
            return Error.Ps2DeviceIssue;
        }

        return read_data_as(MouseStatus, 512);
    }

    fn mouse_data_enabled(port: Port, enabled: bool) Error!void {
        const ack_res = device_command(port, if (enabled) 0xf4 else 0xf5);
        if (ack_res != ack) {
            print.format("WARNING: get_mouse_status: PS/2 device on {} replied {} for ack\n",
                .{port, ack_res});
            return Error.Ps2DeviceIssue;
        }
    }

    fn reset_device(port: Port, device: *?DeviceKind) Error!void {
        device.* = null;

        // Reset: This returns an ack, a self-test result, and a 0 to 2 byte
        // byte sequence id. The last part doesn't seem to be properly
        // documented on the osdev wiki. (TODO?)
        // TODO: Detect no device
        const ack_res = device_command(port, 0xff);
        if (ack_res != ack) {
            print.format("WARNING: reset_device: PS/2 device on {} replied {} for ack\n",
                .{port, ack_res});
            return;
        }

        // Self-test result
        const self_test_res = read_data();
        if (self_test_res != 0xaa) {
            print.format("WARNING: reset_device: PS/2 device on {} replied {} for self test\n",
                .{port, self_test_res});
        }

        // Get id byte sequence
        const timeout: u16 = 2048;
        if (read_data_with_timeout(timeout)) |id0| {
            if (read_data_with_timeout(timeout)) |id1| {
                print.format(" - PS/2 {}: Unknown device {:x}, {:x}\n", .{port, id0, id1});
                device.* = DeviceKind.Unknown;
            } else if (id0 == 0) {
                print.format(" - PS/2 {}: Mouse\n", .{port});
                device.* = DeviceKind.Mouse;
            } else {
                print.format(" - PS/2 {}: Unknown device {:x}\n", .{port, id0});
                device.* = DeviceKind.Unknown;
            }
        } else {
            print.format(" - PS/2 {}: Keyboard\n", .{port});
            device.* = DeviceKind.Keyboard;
        }

        // TODO: Zig bug, can't combine this into a single "and" expr, LLVM crashes
        if (build_options.mouse) {
            if (device.* == DeviceKind.Mouse) {
                const mouse_status = try get_mouse_status(port);
                // print.format("MouseStatus: {}\n", .{mouse_status});
                if (!mouse_status.data_enabled) {
                    try mouse_data_enabled(port, true);
                    // const mouse_status2 = try get_mouse_status(port);
                    // print.format("MouseStatus: {}\n", .{mouse_status2});
                }
            }
        }
    }

    fn reset() Error!void {
        // Disable ports and flush output buffer
        enable_port(.Port1, false);
        enable_port(.Port2, false);
        _ = putil.in8(data_port);
        var config = read_config();
        config.port1_interrupt_enabled = false;
        config.port2_interrupt_enabled = false;
        write_config(config);

        // Controller self-test
        const controller_status = command(0xaa, null, .HasRes).?;
        if (controller_status != 0x55) {
            print.format("ERROR: PS/2 controller self-test status {}\n", .{controller_status});
            return Error.Ps2ResetFailed;
        }

        // Test ports
        const port1_status = command(0xab, null, .HasRes).?;
        if (port1_status != 0x00) {
            print.format("ERROR: PS/2 port 1 test status {}\n", .{port1_status});
            return Error.Ps2ResetFailed;
        }
        const port2_status = command(0xa9, null, .HasRes).?;
        if (port2_status != 0x00) {
            print.format("ERROR: PS/2 port 2 test status {}\n", .{port2_status});
            return Error.Ps2ResetFailed;
        }

        // Enable ports
        enable_port(.Port1, true);
        enable_port(.Port2, true);

        // Set controller config
        config.port1_interrupt_enabled = true;
        config.port2_interrupt_enabled = true;
        // Have controller translate to scan code set 1 for us. That's
        // what's currently in ps2_scan_codes.zig.
        config.port1_translation = true;
        write_config(config);

        // Reset/detect devices on ports
        reset_device(.Port1, &port1_device) catch |e| {
            print.format("ERROR: PS/2 port 1 init error: {}\n", .{@errorName(e)});
            port1_device = null;
        };
        reset_device(.Port2, &port2_device) catch |e| {
            print.format("ERROR: PS/2 port 2 init error: {}\n", .{@errorName(e)});
            port2_device = null;
        };
    }

    const MouseData = packed struct {
        lmb_pressed: bool,
        rmb_pressed: bool,
        mmb_pressed: bool,
        one: u1 = 1,
        x_sign: u1,
        y_sign: u1,
        x_overflow: u1,
        y_overflow: u1,
        x: u8,
        y: u8,

        fn get_value(sign: u1, value: u8) i9 {
            return @bitCast(i9, (@intCast(u9, sign) << 8) | value);
        }

        fn to_mouse_event(self: *const MouseData) MouseEvent {
            return .{
                .rmb_pressed = self.rmb_pressed,
                .mmb_pressed = self.mmb_pressed,
                .lmb_pressed = self.lmb_pressed,
                .delta = .{
                    .x = get_value(self.x_sign, self.x),
                    .y = get_value(self.y_sign, self.y),
                },
            };
        }
    };

    fn get_mouse_data() Error!MouseData {
        return read_data_as(MouseData, 128);
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

fn keyboard_event_occurred(interrupt_number: u32, interrupt_stack: *const interrupts.Stack) void {
    _ = interrupt_number;
    _ = interrupt_stack;
    if (!keyboard_initialized) return;
    var event: ?KeyboardEvent = null;
    const byte = controller.read_data();
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
                    event = KeyboardEvent.new(
                        key, entry.shifted_key, entry.kind.?, &keyboard_modifiers);
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
                        event = KeyboardEvent.new(
                            key, entry.shifted_key, entry.kind.?, &keyboard_modifiers);
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
                    event = KeyboardEvent.new(
                        .Key_PrintScreen, null, .Pressed, &keyboard_modifiers);
                }
                reset = true;
            },

            .PrintScreenReleased => {
                if (byte == 0xaa) {
                    // Reached PrintScreen Released
                    event = KeyboardEvent.new(
                        .Key_PrintScreen, null, .Released, &keyboard_modifiers);
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
                    event = KeyboardEvent.new(.Key_Pause, null, .Hit, &keyboard_modifiers);
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
        keyboard_modifiers.update(e);
        // print.format("<{}: {}>", .{@tagName(e.key), @tagName(e.kind)});
        if (e.kind == .Pressed) {
            if (key_to_char(e.key)) |c| {
                e.char = c;
                if (keyboard_modifiers.alt_is_pressed() and
                        keyboard_modifiers.control_is_pressed() and c == 'D') {
                    kernel.quick_debug();
                    return;
                }
            }
        }
        keyboard_buffer.push(e.*);
        kernel.threading_mgr.keyboard_event_occurred();
    }
}

pub fn get_key() ?KeyboardEvent {
    putil.disable_interrupts();
    defer putil.enable_interrupts();
    return keyboard_buffer.pop();
}

fn mouse_event_occurred(interrupt_number: u32, interrupt_stack: *const interrupts.Stack) void {
    _ = interrupt_number;
    _ = interrupt_stack;
    if (!mouse_initialized) return;
    const data = controller.get_mouse_data() catch return;
    const event = data.to_mouse_event();
    //print.format("mouse: {}\n", .{event});
    mouse_buffer.push(event);
}

pub fn get_mouse_event() ?MouseEvent {
    putil.disable_interrupts();
    defer putil.enable_interrupts();
    return mouse_buffer.pop();
}

pub fn init() !void {
    try controller.reset();

    // Set up IRQs
    if (controller.port1_is_keyboard()) {
        interrupts.IrqInterruptHandler(1, keyboard_event_occurred).set(
            "IRQ1: PS/2 Keyboard", segments.kernel_code_selector, interrupts.kernel_flags);
    }
    if (controller.port2_is_mouse()) {
        interrupts.IrqInterruptHandler(12, mouse_event_occurred).set(
            "IRQ12: PS/2 Mouse", segments.kernel_code_selector, interrupts.kernel_flags);
    }
    interrupts.load();
    if (controller.port1_is_keyboard()) {
        interrupts.pic.allow_irq(1, true);
    }
    if (controller.port2_is_mouse()) {
        interrupts.pic.allow_irq(12, true);
    }

    keyboard_initialized = controller.port1_is_keyboard();
    mouse_initialized = controller.port2_is_mouse();
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
