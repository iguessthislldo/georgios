// ============================================================================
// Universal Serial Bus (USB) Enhanced Host Controller Interface (EHCI)
//
// References:
//   "USB: The Universal Serial Bus" by Benjamin David Lunt 3rd Edition
//
// ============================================================================

const kernel = @import("root").kernel;
const print = kernel.print;
const memory = kernel.memory;

const platform = @import("platform.zig");
const pci = @import("pci.zig");
const interrupts = @import("interrupts.zig");
const segments = @import("segments.zig");
const timing = @import("timing.zig");
const ps2 = @import("ps2.zig");

const Error = memory.MemoryError;

const StructParams = packed struct {
    port_count: u4, // N_PORTS
    port_power_control: bool, // PPC
    reserved0: u2,
    port_routing_rules: bool,
    ports_per_companion: u4, // N_PCC
    companion_count: u4, // N_CC
    port_indicator: bool, // P_INDICATOR
    reserved1: u3,
    debug_port_number: u4,
    reserved2: u8,
};

const CapParams = packed struct {
    has_64b_addr: bool,
    programmable_frame_list: bool,
    async_schedule_park: bool,
    reserved0: bool,
    isochronous_scheduling_threshold: u4,
    extended_caps_offset: u8,
    reserved1: u16, // 4 bits at the start of this are used by v1.1
};

const CapRegs = packed struct {
    length: u8, // CAPLENGTH
    reserved: u8,
    version: u16, // HCIVERSION
    _struct_params: StructParams, // HCSPARAMS
    _cap_params: CapParams, // HCCPARAMS

    pub fn get_struct_params(self: *const CapRegs) StructParams {
        return self._struct_params;
    }

    pub fn get_cap_params(self: *const CapRegs) CapParams {
        return self._cap_params;
    }

    pub fn get(virtual_range: memory.Range) *const CapRegs {
        return @intToPtr(*const CapRegs, virtual_range.start);
    }

    // HCSP-PORTROUTE is after HCCPARAMS, but its size depends on CAPLENGTH and
    // its validity depends on struct_params.
    pub fn get_companion_port_route(self: *const CapRegs, index: usize) ?u4 {
        if (!self.get_struct_params().port_routing_rules) return null;
        const count = (@as(usize, self.length) - @sizeOf(CapRegs)) / 2;
        if (index >= count) return null;
        const byte = @intToPtr(*const u8,
            @ptrToInt(self) + @sizeOf(CapRegs) + index / 2).*;
        return @truncate(u4, byte >> (@truncate(u3, index & 1) << 2));
    }

    pub fn get_op_regs(self: *const CapRegs) *OpRegs {
        return @intToPtr(*OpRegs, @ptrToInt(self) + self.length);
    }

    pub fn get_port_regs(self: *const CapRegs) []PortReg {
        return @intToPtr([*]PortReg, @ptrToInt(self.get_op_regs()) + @sizeOf(OpRegs))
            [0..self.get_struct_params().port_count];
    }

    pub fn get_extended_caps_id_offset(self: *const CapRegs, dev: *pci.Dev, id: u8) ?u8 {
        // Lunt Pages 7-8 and M-7
        var offset = self.get_cap_params().extended_caps_offset;
        while (true) {
            const value = dev.read(u32, offset);
            const this_id = @truncate(u8, value);
            if (this_id == id) {
                return offset;
            }
            const next = @truncate(u8, value >> 8);
            if (next == 0) {
                break;
            }
            offset += next;
        }
        return null;
    }
};

const Command = packed struct {
    // Lunt Table 7-10
    // TODO: Zig Compiler crashes: "TODO buf_read_value_bytes enum packed"
    // const FrameListSize = enum(u2) {
    //     e1024 = 0b00,
    //     e512 = 0b01,
    //     e256 = 0b10,
    //     e32 = 0b11,
    // };

    run: bool, // RS
    reset: bool, // HCRESET
    // frame_list_size: FrameListSize,
    frame_list_size: u2,
    period_schedule_enabled: bool,
    async_schedule_enabled: bool,
    async_doorbell_interrupt: bool,
    light_host_reset: bool,
    async_park_mode_count: u2,
    reserved0: bool,
    async_park_mode_enabled: bool,
    reserved1: u4,
    interrupt_threshold: u8,
    reserved2: u8,

    pub fn init(self: *Command) void {
        var new = @bitCast(Command, @as(u32, 0));
        new.interrupt_threshold = 8;
        // new.async_schedule_enabled = true;
        // new.period_schedule_enabled = true;
        // new.frame_list_size = FrameListSize.e1024;
        new.run = true;
        self.* = new;
    }
};

/// Lunt Table 7-12
const Status = packed struct {
    transfer_interrupt: bool,
    error_interrupt: bool,
    port_change_detect: bool,
    frame_list_rollover: bool,
    host_system_error: bool,
    doorbell_interrupt: bool,
    reserved0: u6,
    halted: bool,
    reclamation: bool,
    periodic_schedule_status: bool,
    async_schedule_status: bool,
    reserved1: u16,

    pub fn clear(self: *Status) void {
        self.* = @bitCast(Status, @as(u32, 0x3f));
    }
};

/// Lunt Table 7-13
const Interrupts = packed struct {
    enabled: bool,
    error_enabled: bool,
    port_change_enabled: bool,
    frame_list_rollover_enabled: bool,
    host_system_error_enabled: bool,
    async_advance_enabled: bool,
    reserved0: u26,
};

/// Lunt Table 7-22
const PortReg = packed struct {
    connected: bool, // Read-only
    status_changed: bool, //
    enabled: bool, // Read/Write only false
    enabled_changed: bool, //
    over_current: bool, // Read-only
    over_current_changed: bool, //
    force_port_resume: bool, // Read/Write
    suspended: bool, // Read/Write
    reset: bool, // Read/Write
    reserved0: bool,
    status: u2, // Read-only
    power: bool, // Read-only or Read/Write if port_power_control is true
    release_ownership: bool, // Read/Write
    indicator_control: u2, //
    test_control: u4, // Read/Write
    wake_on_connect: bool, // Read/Write
    wake_on_disconnect: bool, // Read/Write
    wake_on_over_current: bool, // Read/Write
    reserved1: u9,
};

/// Lunt Table 7-8
const OpRegs = packed struct {
    command: Command, // USBCMD
    status: Status, // USBSTS
    interrupts: Interrupts, // USBINTR
    frame_index: u32, // FRINDEX
    segment_selector: u32, // CTRLDSSEGMENT
    frame_list_address: u32, // PERIODICLISTBASE
    next_async_list: u32, // ASYNCLISTADDR
    reserved: u288,
    config_flag: u32, // CONFIGFLAG
    // PORTSC is after this, see CapRegs.get_port_regs()
};

pub fn interrupt(interrupt_number: u32, interrupt_stack: *const interrupts.Stack) void {
    _ = interrupt_number;
    _ = interrupt_stack;
    print.string("USB INT\n");
}

var frame_list: ?[]u32 = null;

pub fn init(dev: *pci.Dev) void {
    const indent = "      - ";

    // Zero out PCI Capabilities Pointer and Reserved?
    // From Lunt in Step 2 on Chapter 2 Page 10
    dev.write(u32, 0x34, 0);
    dev.write(u32, 0x38, 0);

    // Setup Interrupt Handler
    const irq: u8 = 51;
    interrupts.IrqInterruptHandler(irq, interrupt).set(
        "USB", segments.kernel_code_selector, interrupts.kernel_flags);
    interrupts.load();
    dev.write(u8, 0x3c, irq);

    // Use Memory-Mapped I/O
    // This can be set to 5 to use Port I/O, but memory is easier to use.
    dev.write(u16, 0x04, 0x0006);

    // Map Controller's Address Space
    const physical_range = dev.base_addresses[0].?.memory.range;
    const pmem = &kernel.memory_mgr.impl;
    const range = pmem.get_unused_kernel_space(physical_range.size) catch
        @panic("usb.init: get_unused_kernel_space failed");
    pmem.map(range, physical_range.start, false) catch
        @panic("usb.init: map failed");

    ps2.anykey();

    // Get Controller Registers
    const cap_regs = CapRegs.get(range);
    const op_regs = cap_regs.get_op_regs();

    // Turn Off BIOS USB to PS/2 Emulation
    if (cap_regs.get_cap_params().extended_caps_offset >= 0x40) {
        // Find the USB Legacy Support
        if (cap_regs.get_extended_caps_id_offset(dev, 1)) |offset| {
            // Set the "System Software Owned Semaphore" Bit
            // Lunt Pages M-9
            dev.write(u32, offset, dev.read(u32, offset) | (1 << 24));
        }
    }

    // Reset the Controller
    var reset_timeout: u8 = 30; // Lunt says 20ms, but do 30ms to be safe.
    {
        var copy = op_regs.command;
        copy.run = false;
        copy.reset = true;
        op_regs.command = copy;
    }
    while (reset_timeout > 0) {
        var copy = op_regs.command;
        if (!copy.reset) break;
        timing.wait_milliseconds(1);
        reset_timeout -= 1;
    }
    {
        var copy = op_regs.command;
        if (copy.reset) {
            print.string(indent ++ "EHCI Controller failed to respond to reset\n");
            return;
        }
    }

    print.string(indent ++ "EHCI Controller Reset\n");

    frame_list = kernel.memory_mgr.big_alloc.alloc_array(u32, 1024) catch
        @panic("usb.init: alloc frame_list failed");

    // Initialize the Controller
    var int_copy = op_regs.interrupts;
    int_copy.enabled = true;
    int_copy.error_enabled = true;
    int_copy.port_change_enabled = true;
    op_regs.interrupts = int_copy;
    op_regs.frame_index = 0;
    op_regs.segment_selector = 0;
    op_regs.frame_list_address = @ptrToInt(frame_list.?.ptr);
    // op_regs.next_async_list = 0; // TODO
    op_regs.status.clear();
    op_regs.command.init();
    op_regs.config_flag = 1;

    print.string(indent ++ "EHCI Controller Initialized\n");

    const power_control = cap_regs.get_struct_params().port_power_control;
    for (cap_regs.get_port_regs()) |*port_reg, i| {
        // For some reason the accessing the ports registers in QEMU must be
        // done as a whole.
        var copy = port_reg.*;

        // Check to see if we need to power the port
        if (power_control and !copy.power) {
            copy.power = true;
            port_reg.* = copy;
            timing.wait_milliseconds(30);
            copy = port_reg.*;
        }

        if (!copy.connected) continue; // No device

        // Reset the Port Lunt 7-25
        copy.reset = true;
        copy.enabled = false;
        port_reg.* = copy;
        copy = port_reg.*;
        while (!copy.reset) {
            copy = port_reg.*;
        }
        timing.wait_milliseconds(50);
        copy.reset = false;
        port_reg.* = copy;
        copy = port_reg.*;
        while (copy.reset) {
            copy = port_reg.*;
        }

        if (!copy.enabled) {
            // Not a high-speed device, release ownership to another controller
            copy.release_ownership = true;
            port_reg.* = copy;
            continue;
        }

        print.format("Port {}: {}\n", .{i, copy});
    }
}
