// ============================================================================
// Universal Serial Bus (USB) Enhanced Host Controller Interface (EHCI)
//
// References:
//   "USB: The Universal Serial Bus" by Benjamin David Lunt 3rd Edition
//
// ============================================================================

const print = @import("../print.zig");
const kernel = @import("../kernel.zig");
const memory = @import("../memory.zig");

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

const CapabilityRegisters = packed struct {
    length: u8, // CAPLENGTH
    reserved: u8,
    version: u16, // HCIVERSION
    struct_params: StructParams, // HCSPARAMS
    cap_params: CapParams, // HCCPARAMS

    pub fn get(virtual_range: memory.Range) *const CapabilityRegisters {
        return @intToPtr(*const CapabilityRegisters, virtual_range.start);
    }

    // HCSP-PORTROUTE is after HCCPARAMS, but its size depends on CAPLENGTH and
    // its validity depends on struct_params.
    pub fn get_companion_port_route(self: *const CapabilityRegisters, index: usize) ?u4 {
        if (!self.struct_params.port_routing_rules) return null;
        const count = (@as(usize, self.length) - @sizeOf(CapabilityRegisters)) / 2;
        if (index >= count) return null;
        const byte = @intToPtr(*const u8,
            @ptrToInt(self) + @sizeOf(CapabilityRegisters) + index / 2).*;
        return @truncate(u4, byte >> (@truncate(u3, index & 1) << 2));
    }

    pub fn get_op_regs(self: *const CapabilityRegisters) *OpRegs {
        return @intToPtr(*OpRegs, @ptrToInt(self) + self.length);
    }

    pub fn get_extended_caps_id_offset(
            self: *const CapabilityRegisters, dev: *pci.Dev, id: u8) ?u8 {
        // Lunt Pages 7-8 and M-7
        var offset = self.cap_params.extended_caps_offset;
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
    run: bool, // RS
    reset: bool, // HCRESET
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
};

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
};

const OpRegs = packed struct {
    command: Command, // USBCMD
    status: Status, // USBSTS
    // interrupts: Interrupts, // USBINTR
    // frame_index: Frame, // FRINDEX
    // segment_selector: u32, // CTRLDSSEGMENT
    // frame_list_address: u32, // PERIODICLISTBASE
    // next_async_list: u32, // ASYNCLISTADDR
    // reserved: u288,
    // config_flag: u32, // CONFIGFLAG
    // port_status_control: u32, // PORTSC
};

pub fn interrupt(interrupt_number: u32, interrupt_stack: *const interrupts.Stack) void {
}

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
    const pmem = &kernel.memory.platform_memory;
    const range = pmem.get_unused_kernel_space(physical_range.size) catch
        @panic("usb.init: get_unused_kernel_space failed");
    pmem.map(range, physical_range.start, false) catch
        @panic("usb.init: map failed");

    ps2.anykey();

    // Get Controller Registers
    const cap_regs = CapabilityRegisters.get(range);
    const op_regs = cap_regs.get_op_regs();

    print.format("{}\n", .{cap_regs.*});
    ps2.anykey();
    print.format("{}\n", .{op_regs});
    ps2.anykey();

    // Turn Off BIOS USB to PS/2 Emulation
    if (cap_regs.cap_params.extended_caps_offset >= 0x40) {
        // Find the USB Legacy Support
        if (cap_regs.get_extended_caps_id_offset(dev, 1)) |offset| {
            // Set the "System Software Owned Semaphore" Bit
            // Lunt Pages M-9
            dev.write(u32, offset, dev.read(u32, offset) | (1 << 24));
        }
    }

    // Reset
    var invalid = true;
    var reset_timeout: u8 = 30; // Lunt says 20ms, but do 30ms to be safe.
    op_regs.command.reset = true;
    while (reset_timeout > 0 and op_regs.command.reset) {
        timing.wait_milliseconds(1);
        reset_timeout -= 1;
    }
    if (op_regs.command.reset) {
        print.string(indent ++ "EHCI Controller failed to respond to reset\n");
        return;
    }
    print.string(indent ++ "EHCI Controller Initialized\n");
    ps2.anykey();

    print.format("{}\n", .{cap_regs.*});
    print.format("{}\n", .{op_regs});
}
