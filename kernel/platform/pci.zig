// PCI Interface
// Based on https://wiki.osdev.org/PCI

const builtin = @import("builtin");

const utils = @import("utils");

const kernel = @import("root").kernel;
const print = kernel.print;
const fprint = kernel.fprint;
const io = kernel.io;
const memory = kernel.memory;

const putil = @import("util.zig");
const ata = @import("ata.zig");
const ps2 = @import("ps2.zig");
const usb = @import("usb.zig");

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
        return utils.int_to_enum(@This(), value);
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

pub const Bus = u8;
pub const Device = u5;
pub const Function = u3;
pub const Offset = u8;

pub const Location = packed struct {
    function: Function,
    device: Device,
    bus: Bus,
};

const Config = packed struct {
    offset: Offset,
    location: Location,
    reserved: u7 = 0,
    enabled: bool = true,
};

fn config_port(comptime Type: type, location: Location, offset: Offset) callconv(.Inline) u16 {
    const config = Config{
        .offset = offset & 0xFC,
        .location = location,
    };
    putil.out(u32, 0x0CF8, @bitCast(u32, config));
    return 0x0CFC + @intCast(u16, if (Type == u32) 0 else (offset & 3));
}

pub fn read_config(comptime Type: type,
        location: Location, offset: Offset) callconv(.Inline) Type {
    return putil.in(Type, config_port(Type, location, offset));
}

pub fn write_config(comptime Type: type,
        location: Location, offset: Offset, value: Type) callconv(.Inline) void {
    putil.out(Type, config_port(Type, location, offset), value);
}

pub const Header = packed struct {
    pub const Kind = packed enum (u8) {
        Normal = 0x00,
        MultiFunctionNormal = 0x80,
        PciToPciBridge = 0x01,
        MultiFunctionPciToPciBridge = 0x81,
        CardBusBridge = 0x02,
        MultiFunctionCardBusBridge = 0x82,

        pub fn from_u8(value: u8) ?Kind {
            return utils.int_to_enum(@This(), value);
        }

        pub fn to_string(self: Kind) []const u8 {
            return switch (self) {
                .Normal => "Normal",
                .MultiFunctionNormal => "Multi-Function Normal",
                .PciToPciBridge => "PCI-to-PCI Bridge",
                .MultiFunctionPciToPciBridge =>
                    "Multi-Function PCI-to-PCI Bridge",
                .CardBusBridge => "CardBus Bridge",
                .MultiFunctionCardBusBridge =>
                    "Multi-Function CardBus Bridge",
            };
        }

        pub fn is_multifunction(self: Kind) bool {
            return switch (self) {
                .MultiFunctionNormal => true,
                .MultiFunctionPciToPciBridge => true,
                .MultiFunctionCardBusBridge => true,
                else => false,
            };
        }
    };

    pub const SuperClass = packed enum (u8) {
        UnclassifiedDevice = 0x00,
        MassStorageController = 0x01,
        NetworkController = 0x02,
        DisplayController = 0x03,
        MultimediaController = 0x04,
        MemoryController = 0x05,
        BridgeDevice = 0x06,
        SimpleCommunicationsController = 0x07,
        GenericSystemPeripheral = 0x08,
        InputDeviceController = 0x09,
        DockingStation = 0x0A,
        Processor = 0x0B,
        SerialBusController = 0x0C,
        WirelessController = 0x0D,
        IntelligentController = 0x0E,
        SatelliteCommunicationsController = 0x0F,
        EncryptionController = 0x10,
        SignalProcessingController = 0x11,
        ProcessingAccelerator = 0x12,
        NonEssentialInstrumentation = 0x13,
        Coprocessor = 0x40,

        pub fn from_u8(value: u8) ?SuperClass {
            return utils.int_to_enum(@This(), value);
        }

        pub fn to_string(self: SuperClass) []const u8 {
            return switch (self) {
                .UnclassifiedDevice => "Unclassified Device",
                .MassStorageController => "Mass Storage Controller",
                .NetworkController => "Network Controller",
                .DisplayController => "Display Controller",
                .MultimediaController => "Multimedia Controller",
                .MemoryController => "Memory Controller",
                .BridgeDevice => "Bridge Device",
                .SimpleCommunicationsController =>
                    "Simple Communications Controller",
                .GenericSystemPeripheral => "Generic System Peripheral",
                .InputDeviceController => "Input Device Controller",
                .DockingStation => "Docking Station",
                .Processor => "Processor",
                .SerialBusController => "Serial Bus Controller",
                .WirelessController => "Wireless Controller",
                .IntelligentController => "Intelligent Controller",
                .SatelliteCommunicationsController =>
                    "Satellite Communications Controller",
                .EncryptionController => "Encryption Controller",
                .SignalProcessingController => "Signal Processing Controller",
                .ProcessingAccelerator => "Processing Accelerator",
                .NonEssentialInstrumentation =>
                    "Non-Essential Instrumentation",
                .Coprocessor => "Coprocessor",
            };
        }
    };

    vendor_id: u16 = 0,
    device_id: u16 = 0,
    command: u16 = 0,
    status: u16 = 0,
    revision_id: u8 = 0,
    prog_if: u8 = 0,
    subclass: u8 = 0,
    class: u8 = 0,
    cache_line_size: u8 = 0,
    latency_timer: u8 = 0,
    header_type: u8 = 0,
    bist: u8 = 0,

    pub fn is_invalid(self: *const Header) bool {
        return self.vendor_id == 0xFFFF;
    }

    pub fn get_header_type(self: *const Header) ?Kind {
        return Kind.from_u8(self.header_type);
    }

    pub fn get_class(self: *const Header) ?SuperClass {
        return SuperClass.from_u8(self.class);
    }

    pub fn print(self: *const Header, file: *io.File) io.FileError!void {
        try fprint.format(file,
            \\     - PCI Header:
            \\       - vendor_id: {:x}
            \\       - device_id: {:x}
            \\       - command: {:x}
            \\       - status: {:x}
            \\       - revision_id: {:x}
            \\       - prog_if: {:x}
            \\       - subclass: {:x}
            \\       - class:
            , .{
            self.vendor_id,
            self.device_id,
            self.command,
            self.status,
            self.revision_id,
            self.prog_if,
            self.subclass});
        if (self.get_class()) |class| {
            try fprint.format(file, " {}", .{class.to_string()});
        } else {
            try fprint.format(file, " Unknown Class {:x}", .{self.class});
        }
        try fprint.format(file,
            \\
            \\       - cache_line_size: {:x}
            \\       - latency_timer: {:x}
            \\       - header_type:
            , .{
            self.cache_line_size,
            self.latency_timer});
        if (self.get_header_type()) |header_type| {
            try fprint.format(file, " {}", .{header_type.to_string()});
        } else {
            try fprint.format(file, " Unknown Value {:x}", .{self.header_type});
        }
        try fprint.format(file,
            \\
            \\       - bist: {:x}
            \\
            , .{self.bist});
    }

    pub fn get(location: Location) Header {
        const Self = @This();
        var rv: [@sizeOf(Self)]u8 = undefined;
        for (rv[0..]) |*ptr, i| {
            ptr.* = read_config(u8, location, @intCast(Offset, i));
        }
        return @bitCast(Self, rv);
    }
};

pub const Dev = struct {
    pub const BaseAddress = union(enum) {
        // TODO
        // Io: struct {
        //     port: u16,
        // },
        memory: struct {
            range: memory.Range,
            // TODO
            // prefetchable: bool,
            // is64b: bool,
        },
    };

    location: Location,
    header: Header,
    base_addresses: [6]?BaseAddress = [_]?BaseAddress {null} ** 6,

    fn read_base_addresses(self: *Dev) void {
        for (self.base_addresses[0..]) |*ptr, i| {
            const offset = @sizeOf(Header) + 4 * @intCast(Offset, i);
            const raw_entry = read_config(u32, self.location, offset);
            if (raw_entry == 0) {
                continue;
            }
            if (raw_entry & 1 == 1) {
                // TODO
                print.format("       - BAR {}: I/O Entry (TODO)\n", .{i});
                continue;
            }

            const address = raw_entry & ~@as(u32, 0xf);

            write_config(u32, self.location, offset, 0xffffffff);
            const size = ~(read_config(u32, self.location, offset) & ~@as(u32, 1)) +% 1;
            write_config(u32, self.location, offset, raw_entry);

            print.format("       - BAR {}: {:a}+{:x}\n", .{i, address, size}, );
            ptr.* = BaseAddress{.memory = .{.range = .{.start = address, .size = size}}};
        }
    }

    pub fn init(self: *Dev) void {
        if (self.header.get_header_type()) |header_type| {
            if (header_type == .Normal) {
                self.read_base_addresses();
            }
        }
    }

    pub fn read(self: *Dev, comptime Type: type, offset: Offset) Type {
        return read_config(Type, self.location, offset);
    }

    pub fn write(self: *Dev, comptime Type: type, offset: Offset, value: Type) void {
        write_config(Type, self.location, offset, value);
    }
};

fn check_function(location: Location, header: *const Header) void {
    if (header.is_invalid()) return;
    print.format("   - Bus {}, Device {}, Function {}\n",
        .{location.bus, location.device, location.function});
    _ = header.print(print.get_console_file().?) catch {};
    if (header.get_class()) |class| {
        var dev = Dev{.location = location, .header = header.*};
        dev.init();
        if (class == .MassStorageController and header.subclass == 0x01) {
            ata.init(&dev);
        } else if (class == .SerialBusController and header.subclass == 0x03 and
                header.prog_if == 0x20) {
            usb.init(&dev);
        }
        ps2.anykey();
        if (class == .BridgeDevice and header.subclass == 0x04) {
            check_bus(read_config(u8, location, 0x19));
        }
    }
}

fn check_device(bus: Bus, device: Device) void {
    const root_location = Location{.bus = bus, .device = device, .function = 0};
    const header = Header.get(root_location);
    check_function(root_location, &header);
    if (header.get_header_type()) |header_type| {
        if (header_type.is_multifunction()) {
            // Header Type is Multi-Function, Check Them
            var i: Function = 1;
            while (true) : (i += 1) {
                const location = Location{
                    .bus = bus, .device = device, .function = i};
                const subheader = Header.get(location);
                check_function(location, &subheader);
                if (i == 7) break;
            }
        }
    }
}

fn check_bus(bus: u8) void {
    var i: Device = 0;
    while (true) : (i += 1) {
        check_device(bus, i);
        if (i == 31) break;
    }
}

pub fn find_pci_devices() void {
    print.string(" - Seaching for PCI Devices\n");
    check_bus(0);
}
