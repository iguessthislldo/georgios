// PCI Interface
// Based on https://wiki.osdev.org/PCI

const builtin = @import("builtin");

const kutil = @import("../util.zig");
const print = @import("../print.zig");

const putil = @import("util.zig");

// Fields Common to all PCI Structures
// Offset | Size | Name
// 0x00   | 2    | Vendor ID
// 0x02   | 2    | Device ID
// 0x04   | 2    | Command
// 0x06   | 2    | Status
// 0x08   | 1    | Revision ID
// 0x09   | 1    | Prog IF
// 0x0A   | 1    | Subclass
// 0x0B   | 1    | Class
// 0x0C   | 1    | Cache Line Size
// 0x0D   | 1    | Latency Timer
// 0x0E   | 1    | Header Type
// 0x0F   | 1    | BIST

const Class = enum (u16) {
    IDE_Controller = 0x0101,
    Floppy_Controller = 0x0102,
    ATA_Controller = 0x0105,
    SATA_Controller = 0x0106,
    Ethernet_Controller = 0x0200,
    VGA_Controller = 0x0300,
    PCI_Host_Bridge = 0x0600,
    ISA_Bridge = 0x0601,
    PCI_To_PCI_Bridge = 0x0604,
    Bridge = 0x0680,
    USB_Controller = 0x0C03,
    Unknown = 0xFFFF,

    pub fn from_u16(value: u16) ?Class {
        return kutil.int_to_enum(Class, value);
    }

    pub fn to_string(self: Class) []const u8 {
        return switch (self) {
            .IDE_Controller => "IDE Controller",
            .Floppy_Controller => "Floppy Controller",
            .ATA_Controller => "ATA Controller",
            .SATA_Controller => "SATA Controller",
            .Ethernet_Controller => "Ethernet Controller",
            .VGA_Controller => "VGA Controller",
            .PCI_Host_Bridge => "PCI Host Bridge",
            .ISA_Bridge => "ISA Bridge",
            .PCI_To_PCI_Bridge => "PCI to PCI Bridge",
            .Bridge => "Bridge",
            .USB_Controller => "USB Controller",
            .Unknown => "Unknown",
        };
    }
};

const Bus = u8;
const Device = u5;
const Function = u3;
const Offset = u8;

pub inline fn read_config16(bus: Bus, device: Device, function: Function,
        offset: Offset) u16 {
    const Config = packed struct {
        offset: Offset,
        function: Function,
        device: Device,
        bus: Bus,
        reserved: u7 = 0,
        enabled: bool = true,
    };
    const config = Config{
        .bus = bus,
        .device = device,
        .function = function,
        .offset = offset & 0xFC,
    };
    putil.out32(0x0CF8, @bitCast(u32, config));

    return @intCast(u16, (putil.in32(0x0CFC) >>
        @intCast(u5, (offset & 2) * 8) & 0xFFFF));
}

pub inline fn read_config8(bus: Bus, device: Device, function: Function,
        offset: Offset) u8 {
    const x: u8 = @intCast(u8, read_config16(
        bus, device, function, offset) >> @intCast(u4, offset * 8));
    print.debug_format("{}\n", x);
    return x;
}

pub inline fn get_vendor_id(bus: Bus, device: Device, function: Function) u16 {
    return read_config16(bus, device, function, 0);
}

pub inline fn get_class(bus: Bus, device: Device, function: Function) u16 {
    return read_config16(bus, device, function, 0xB);
}

pub inline fn get_header_type(bus: Bus, device: Device, function: Function) u16 {
    return read_config16(bus, device, function, 0xE);
}

pub inline fn check_function(bus: Bus, device: Device, function: Function) void {
    const class_value: u16 = get_class(bus, device, function);
    const class_maybe: ?Class = Class.from_u16(class_value);
    if (class_maybe) |class| {
        if (class == .PCI_To_PCI_Bridge) {
            check_bus(read_config8(bus, device, function, 0x19));
        } else {
            print.debug_format(" - Found PCI Device: {} at ({}, {}, {})\n",
                class.to_string(), bus, device, function);
        }
    } else if (class_value != 0xffff) {
        print.debug_format(" - Found Unknown PCI Device: {:x}  at ({}, {}, {})\n",
            class_value, bus, device, function);
    }
}

pub inline fn check_device(bus: Bus, device: Device) void {
    if (get_vendor_id(bus, device, 0) == 0xFFFF) return;
    check_function(bus, device, 0);
    const is_multi: bool = get_header_type(bus, device, 0) & 0x0080 != 0;
    if (is_multi) {
        // Header Type is Multi-Function, Check Them
        var i: Function = 1;
        while (true) : (i += 1) {
            if (get_vendor_id(bus, device, i) != 0xFFFF) {
                check_function(bus, device, i);
            }
            if (i == 7) break;
        }
    }
}

pub fn check_bus(bus: u8) void {
    var i: Device = 0;
    while (true) : (i += 1) {
        check_device(bus, i);
        if (i == 31) break;
    }
}

pub fn find_pci_devices() void {
    check_bus(0);
}
