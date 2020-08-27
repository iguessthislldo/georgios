const print = @import("../print.zig");

const pci = @import("pci.zig");
const putil = @import("util.zig");

pub const Error = error {
    FailedToSelectDrive,
    Timeout,
    UnexpectedValues,
    OperationError,
};

const log_indent = "     ";

const Sector = struct {
    pub const size = 512;

    address: u32,
    data: [size]u8,
};

const CommandStatus = packed struct {
    in_error: bool,
    unused_index: bool,
    unused_corrected: bool,
    data_ready: bool,
    unused_seek_complete: bool,
    fault: bool,
    drive_ready: bool,
    busy: bool,

    pub fn assert_selectable(self: *CommandStatus) Error!void {
        if (self.busy or self.data_ready) {
            return Error.FailedToSelectDrive;
        }
    }

    // TODO: Make these checks simpler?
    pub fn drive_is_ready(self: *CommandStatus) Error!bool {
        if (self.busy) {
            return false;
        }
        if (self.in_error or self.fault) {
            return Error.OperationError;
        }
        return self.drive_ready;
    }

    pub fn data_is_ready(self: *CommandStatus) Error!bool {
        if (self.busy) {
            return false;
        }
        if (self.in_error or self.fault) {
            return Error.OperationError;
        }
        return self.data_ready;
    }

    pub fn print(self: *const CommandStatus) void {
        print.format(
            \\in_error: {}
            \\unused_index: {}
            \\unused_corrected: {}
            \\data_ready: {}
            \\unused_seek_complete: {}
            \\fault: {}
            \\drive_ready: {}
            \\busy: {}
            \\
            ,
            self.in_error,
            self.unused_index,
            self.unused_corrected,
            self.data_ready,
            self.unused_seek_complete,
            self.fault,
            self.drive_ready,
            self.busy);
    }
};

const Control = packed struct {
    unused_bit_0: bool = false,
    interrupts_disabled: bool,
    reset: bool,
    unused_bits_3_7: u5 = 0,
};

const DriveHeadSelect = packed struct {
    lba28_bits_24_27: u4 = 0,
    select_slave: bool,
    always_1_bit_5: bool = true,
    lba: bool = false,
    always_1_bit_7: bool = true,
};

const Controller = struct {
    const default_primary_io_base_port: u16 = 0x01F0;
    const default_primary_control_base_port: u16 = 0x03F4;
    const default_primary_irq: u8 = 14;
    const default_secondary_io_base_port: u16 = 0x0170;
    const default_secondary_control_base_port: u16 = 0x0374;
    const default_secondary_irq: u8 = 16;

    pub const Device = struct {
        pub const Id = enum(u1) {
            Master,
            Slave,
        };
        id: Id,
        present: bool = false,
        selected: bool = false,

        fn get_channel(self: *Device) *Channel {
            return if (self.id == .Master) @fieldParentPtr(Channel, "master", self)
                else @fieldParentPtr(Channel, "slave", self);
        }

        pub fn select(self: *Device) Error!void {
            // TODO
            // if (self.selected) return;

            const channel = self.get_channel();

            try channel.read_command_status().assert_selectable();
            channel.write_select(self.id);
            putil.wait_microseconds(1);
            _ = channel.read_command_status();
            try channel.read_command_status().assert_selectable();
            // self.selected = true;
            // channel.selected(self.id);
        }

        const wait_timeout_ms = 5000;

        // TODO: Merge these wait functions?
        pub fn wait_while_busy(self: *Device) Error!void {
            const channel = self.get_channel();
            var milliseconds_left: u64 = wait_timeout_ms;
            while (channel.read_command_status().busy) {
                milliseconds_left -= 1;
                if (milliseconds_left == 0) {
                    print.string("wait_while_busy Timeout\n");
                    return Error.Timeout;
                }
                putil.wait_milliseconds(1);
            }
        }

        pub fn wait_for_drive(self: *Device) Error!void {
            const channel = self.get_channel();
            var milliseconds_left: u64 = wait_timeout_ms;
            _ = channel.read_control_status();
            while (!try channel.read_control_status().drive_is_ready()) {
                milliseconds_left -= 1;
                if (milliseconds_left == 0) {
                    print.string("wait_for_drive Timeout\n");
                    channel.read_control_status().print();
                    return Error.Timeout;
                }
                putil.wait_milliseconds(1);
            }
        }

        pub fn wait_for_data(self: *Device) Error!void {
            const channel = self.get_channel();
            var milliseconds_left: u64 = wait_timeout_ms;
            _ = channel.read_control_status();
            while (!try channel.read_control_status().data_is_ready()) {
                milliseconds_left -= 1;
                if (milliseconds_left == 0) {
                    print.string("wait_for_data Timeout\n");
                    return Error.Timeout;
                }
                putil.wait_milliseconds(1);
            }
        }

        pub fn reset(self: *Device) Error!void {
            try self.select();

            const channel = self.get_channel();

            // Enable Reset
            channel.write_control(Control{.interrupts_disabled = true, .reset = true});
            // Wait 5+ us
            putil.wait_microseconds(5);

            // Disable Reset
            channel.write_control(Control{.interrupts_disabled = true, .reset = false});
            // Wait 2+ ms
            putil.wait_milliseconds(2);

            // Wait for controller to stop being busy
            try self.wait_while_busy();
            // Wait 5+ ms
            putil.wait_milliseconds(5);
            _ = channel.read_error();

            // Read Expected Values
            const sector_count = channel.read_sector_count();
            const sector_number = channel.read_sector_number();
            if (sector_count != 1 and sector_number != 1) {
                print.format(log_indent ++ "    - reset: expected 1, 1 for sector count "
                    ++ "and number, but got {}, {}\n", sector_count, sector_number);
                return Error.UnexpectedValues;
            }
            print.format(log_indent ++ "    - type: {:x}\n", channel.read_cylinder());
        }

        pub fn initialize(self: *Device) Error!void {
            print.format(log_indent ++ "  - {}\n",
                if (self.id == .Master) "Master" else "Slave");
            const channel = self.get_channel();
            try self.reset();

            try self.wait_for_drive();
            channel.identify_command();
            _ = channel.read_command_status();
            try self.wait_for_data();
            var sector: Sector = undefined;
            channel.read_sector(&sector);
            print.data(@ptrToInt(&sector.data[0]), sector.data.len);
        }

        pub fn read(self: *Device, sector: *Sector) Error!void {
            const channel = self.get_channel();
            channel.write_sector_count(1);
            channel.write_lba(sector.address);
            channel.read_sectors_command();
            putil.wait_microseconds(5);
            try self.wait_while_busy();
            const error_reg = channel.read_error();
            const status_reg = channel.read_command_status();
            if (((error_reg & 0x80) != 0) || status.in_error || status.fault) {
                print.format("ATA Read Error\n");
                return Error.OperationError;
            }
            channel.read_sector(sector);
        }
    };

    const Channel = struct {
        pub const Id = enum(u1) {
            Primary,
            Secondary,
        };
        id: Id,
        io_base_port: u16,
        control_base_port: u16,
        irq: u8,
        master: Device = Device{
            .id = Device.Id.Master,
        },
        slave: Device = Device{
            .id = Device.Id.Slave,
        },

        pub fn selected(self: *Channel, id: Device.Id) void {
            if (id == Device.Id.Master) {
                self.slave.selected = false;
            } else {
                self.master.selected = false;
            }
        }

        pub fn read_command_status(self: *Channel) CommandStatus {
            return @bitCast(CommandStatus, putil.in8(self.io_base_port + 7));
        }

        pub fn read_control_status(self: *Channel) CommandStatus {
            return @bitCast(CommandStatus, putil.in8(self.control_base_port + 2));
        }

        pub fn read_error(self: *Channel) u8 { // TODO: Create Struct?
            return putil.in8(self.io_base_port + 1);
        }

        pub fn read_sector_count(self: *Channel) u8 {
            return putil.in8(self.io_base_port + 2);
        }

        pub fn write_sector_count(self: *Channel, value: u8) u8 {
            return putil.out8(self.io_base_port + 2, value);
        }

        pub fn read_sector_number(self: *Channel) u8 {
            return putil.in8(self.io_base_port + 3);
        }

        pub fn read_cylinder(self: *Channel) u16 {
            const low = @intCast(u16, putil.in8(self.io_base_port + 4));
            const high = @intCast(u16, putil.in8(self.io_base_port + 5));
            return (high << 8) | low;
        }

        pub fn write_drive_head_select(self: *Channel, value: DriveHeadSelect) void {
            putil.out8(self.io_base_port + 6, @bitCast(u8, value));
        }

        pub fn write_select(self: *Channel, value: Device.Id) void {
            self.write_drive_head_select(DriveHeadSelect{.select_slave = value == Device.Id.Slave});
        }

        pub fn write_lba(self: *Channel, device: Device.Id, lba: u32) void {
            putil.out8(self.io_base_port + 3, @truncate(u8, lba));
            putil.out8(self.io_base_port + 4, @truncate(u8, lba >> 8));
            putil.out8(self.io_base_port + 5, @truncate(u8, lba >> 16));
            self.write_drive_head_select(DriveHeadSelect{
                .lba = true,
                .master = value == Device.Id.Master,
                .lba28_bits_24_27 = @truncate(u4, lba >> 24),
            });
        }

        pub fn read_sectors_command(self: *Channel) void {
            putil.out8(self.io_base_port + 7, 0x24);
        }

        pub fn identify_command(self: *Channel) void {
            putil.out8(self.io_base_port + 7, 0xEC);
        }

        pub fn write_control(self: *Channel, value: Control) void {
            putil.out8(self.control_base_port + 2, @bitCast(u8, value));
        }

        pub fn read_sector(self: *Channel, sector: *Sector) void {
            putil.insw(self.io_base_port + 0, sector.data[0..]);
        }

        pub fn initialize(self: *Channel) void {
            print.format(log_indent ++ "- {}\n",
                if (self.id == .Primary) "Primary" else "Secondary");
            self.master.initialize() catch {
                print.format(log_indent ++ "  - Master Failed\n");
            };
            self.slave.initialize() catch {
                print.format(log_indent ++ "  - Slave Failed\n");
            };
        }
    };

    pci_location: pci.Location = undefined,
    primary: Channel = Channel{
        .id = Channel.Id.Primary,
        .io_base_port = default_primary_io_base_port,
        .control_base_port = default_primary_control_base_port,
        .irq = default_primary_irq,
    },
    secondary: Channel = Channel{
        .id = Channel.Id.Secondary,
        .io_base_port = default_secondary_io_base_port,
        .control_base_port = default_secondary_control_base_port,
        .irq = default_secondary_irq,
    },

    pub fn initialize(self: *Controller, location: pci.Location, header: *const pci.Header) void {
        self.pci_location = location;

        // Make sure this is Triton II controller emulated by QEMU
        if (header.vendor_id != 0x8086 or header.device_id != 0x7010 or header.prog_if != 0x80) {
            print.string(log_indent ++ "- Unknown IDE Controller\n");
            return;
        }

        // Would use to access PCI provided information if needed
        // const normal_header = pci.NormalHeader.get(location);
        // _ = normal_header.print(print.get_console_file().?) catch {};

        self.primary.initialize();
        self.secondary.initialize();
    }
};

// TODO: Make dynamic
var controller = Controller{};

pub fn initialize(location: pci.Location, header: *const pci.Header) void {
    controller.initialize(location, header);
}
