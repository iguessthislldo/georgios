const print = @import("../print.zig");
const kutil = @import("../util.zig");
const io = @import("../io.zig");
const memory = @import("../memory.zig");
const MemoryError = memory.MemoryError;
const Allocator = memory.Allocator;
const devices = @import("../devices.zig");
const Kernel = @import("../kernel.zig").Kernel;

const pci = @import("pci.zig");
const putil = @import("util.zig");

pub const Error = error {
    FailedToSelectDrive,
    Timeout,
    UnexpectedValues,
    OperationError,
} || MemoryError;

const log_indent = "     ";

const Sector = struct {
    pub const size: u64 = 512;

    address: u64,
    data: [size]u8 align(8) = undefined,

    pub fn dump(self: *const Sector) void {
        print.data(@ptrToInt(&self.data[0]), self.data.len);
    }
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

const IndentifyResults = struct {
    const Raw = packed struct {
        // Word 0
        unused_word_0_bits_0_14: u15,
        is_atapi: bool,
        // Words 1 - 9
        unused_words_1_9: [9]u16,
        // Words 10 - 19
        serial_number: [10]u16,
        // Words 20 - 22
        used_words_20_22: [3]u16,
        // Words 23 - 26
        firmware_revision: [4]u16,
        // Words 27 - 46
        model: [20]u16,
        // Words 47 - 48
        used_words_47_48: [2]u16,
        // Word 49
        unused_word_49_bits_0_8: u9,
        lba: bool,
        unused_word_49_bits_10_15: u6,
        // Words 50 - 59
        unused_words_50_59: [10]u16,
        // Words 60 - 61
        lba28_sector_count: u32,
        // Words 62 - 85
        unused_words_62_85: [24]u16,
        // Word 86
        unused_word_86_bits_0_9: u10,
        lba48: bool,
        unused_word_86_bits_11_15: u5,
        // Words 87 - 99
        unused_words_87_99: [13]u16,
        // Words 100 - 103
        lba48_sector_count: u64,
        // Words 104 - 255
        unused_words_104_255: [152]u16,
    };

    comptime {
        const raw_bit_size = kutil.packed_bit_size(Raw);
        const sector_bit_size = Sector.size * 8;
        if (raw_bit_size != sector_bit_size) {
            @compileLog("IndentifyResults.Raw is ", raw_bit_size, " bits");
            @compileLog("Sector is ", sector_bit_size, " bits");
            @compileError("IndentifyResults.Raw must match the size of a sector");
        }
    }

    const AddressType = enum(u8) {
        Lba28,
        Lba48,

        pub fn to_string(self: AddressType) []const u8 {
            return switch (self) {
                .Lba28 => "LBA 28",
                .Lba48 => "LBA 48",
            };
        }
    };

    model: []u8,
    sector_count: u64,
    address_type: AddressType,

    pub fn from_sector(sector: *Sector) Error!IndentifyResults {
        var results: IndentifyResults = undefined;
        const raw = @ptrCast(*Raw, &sector.data[0]);

        results.model.ptr = @ptrCast([*]u8, &raw.model[0]);
        results.model.len = raw.model.len * 2;
        for (raw.model) |*i| {
            i.* = @byteSwap(u16, i.*);
        }
        results.model.len = kutil.stripped_string_size(results.model);
        // TODO: Other Strings

        if (raw.lba) {
            if (raw.lba48) {
                results.address_type = .Lba48;
                results.sector_count = raw.lba48_sector_count;
            } else {
                results.address_type = .Lba28;
                results.sector_count = raw.lba28_sector_count;
            }
        } else {
            print.string("Error: Drive does not support LBA\n");
            return Error.UnexpectedValues;
        }

        return results;
    }
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
        alloc: *memory.Allocator = undefined,
        block_store_interface: io.BlockStore = undefined,

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
                    print.format("wait_for_drive Timeout {}\n", channel.read_control_status());
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

        pub fn initialize(self: *Device, temp_sector: *Sector, alloc: *memory.Allocator) Error!void {
            print.format(log_indent ++ "  - {}\n",
                if (self.id == .Master) "Master" else "Slave");
            const channel = self.get_channel();
            self.alloc = alloc;
            try self.reset();

            try self.wait_for_drive();
            channel.identify_command();
            _ = channel.read_command_status();
            try self.wait_for_data();
            channel.read_sector(temp_sector);
            const identity = try IndentifyResults.from_sector(temp_sector);
            print.format(
                log_indent ++ "    - Drive Model: \"{}\"\n", identity.model);
            print.format(
                log_indent ++ "    - Address Type: {}\n",
                identity.address_type.to_string());
            print.format(
                log_indent ++ "    - Sector Count: {}\n",
                @intCast(usize, identity.sector_count));
            self.present = true;
            self.block_store_interface.block_size = Sector.size;
            self.block_store_interface.read_block_impl = Device.read_block;
            self.block_store_interface.free_block_impl = Device.free_block;
        }

        pub fn read_impl(self: *Device, address: u64, data: []u8) Error!void {
            try self.select();
            const channel = self.get_channel();
            try self.wait_for_drive();
            channel.write_lba48(self.id, address, 1);
            putil.wait_microseconds(5);
            channel.read_sectors_command();
            _ = channel.read_command_status();
            const error_reg = channel.read_error();
            const status_reg = channel.read_command_status();
            if (((error_reg & 0x80) != 0) or status_reg.in_error or status_reg.fault) {
                print.format("ATA Read Error\n");
                return Error.OperationError;
            }
            try self.wait_for_data();
            channel.read_sector_impl(data);
        }

        pub fn read_sector(self: *Device, sector: *Sector) Error!void {
            try self.read_impl(sector.address, sector.data[0..]);
        }

        pub fn read_block(block_store: *io.BlockStore, block: *io.Block) io.BlockError!void {
            const self = @fieldParentPtr(Device, "block_store_interface", block_store);
            if (block.data == null) {
                block.data = try self.alloc.alloc_array(u8, Sector.size);
            }
            self.read_impl(block.address, block.data.?[0..])
                catch return io.BlockError.Internal;
        }

        pub fn free_block(block_store: *io.BlockStore, block: *io.Block) io.BlockError!void {
            const self = @fieldParentPtr(Device, "block_store_interface", block_store);
            if (block.data) |data| {
                try self.alloc.free_array(data);
            }
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
            self.write_drive_head_select(
                DriveHeadSelect{.select_slave = value == Device.Id.Slave});
        }

        const sector_count_register = 2;
        const lba_low_register = 3;
        const lba_mid_register = 4;
        const lba_high_register = 5;
        const drive_head_register = 6;

        pub fn write_lba48(self: *Channel,
                device: Device.Id, lba: u64, sector_count: u16) void {
            putil.out8(self.io_base_port + sector_count_register,
                @truncate(u8, sector_count >> 8));
            putil.out8(self.io_base_port + lba_low_register,
                @truncate(u8, lba >> 24));
            putil.out8(self.io_base_port + lba_mid_register,
                @truncate(u8, lba >> 32));
            putil.out8(self.io_base_port + lba_high_register,
                @truncate(u8, lba >> 40));
            putil.out8(self.io_base_port + sector_count_register,
                @truncate(u8, sector_count));
            putil.out8(self.io_base_port + lba_low_register,
                @truncate(u8, lba));
            putil.out8(self.io_base_port + lba_mid_register,
                @truncate(u8, lba >> 8));
            putil.out8(self.io_base_port + lba_high_register,
                @truncate(u8, lba >> 16));
            self.write_drive_head_select(DriveHeadSelect{
                .lba = true,
                .select_slave = device == Device.Id.Slave,
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
            self.read_sector_impl(sector.data[0..]);
        }

        pub fn read_sector_impl(self: *Channel, data: []u8) void {
            putil.insw(self.io_base_port + 0, data);
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
    device_interface: devices.Device = undefined,
    alloc: *Allocator = undefined,

    pub fn initialize(self: *Controller,
            alloc: *Allocator, location: pci.Location, header: *const pci.Header) void {
        self.pci_location = location;
        self.alloc = alloc;
        self.device_interface.deinit_impl = Controller.deinit;

        // Make sure this is Triton II controller emulated by QEMU
        if (header.vendor_id != 0x8086 or header.device_id != 0x7010 or
                header.prog_if != 0x80) {
            print.string(log_indent ++ "- Unknown IDE Controller\n");
            return;
        }

        // Would use to access PCI provided information if needed
        // const normal_header = pci.NormalHeader.get(location);
        // _ = normal_header.print(print.get_console_file().?) catch {};

        // TODO Better error handling
        const temp_sector = alloc.alloc(Sector) catch @panic("ATA init alloc error");
        defer alloc.free(temp_sector) catch @panic("ATA init free error");

        // self.primary.initialize();
        // self.secondary.initialize();
        self.primary.master.initialize(temp_sector, alloc) catch |e| {
            print.string("Drive Initialize Failed\n");
            return;
        };
    }

    pub fn deinit(device: *devices.Device) anyerror!void {
        const self = @fieldParentPtr(Controller, "device_interface", device);
        try self.alloc.free(self);
    }
};

pub fn initialize(kernel: *Kernel, location: pci.Location,
        header: *const pci.Header) void {
    var controller = kernel.memory.small_alloc.alloc(Controller) catch {
        @panic("Failure");
    };
    controller.* = Controller{};
    controller.initialize(kernel.memory.small_alloc, location, header);
    kernel.devices.add_device(&controller.device_interface) catch {
        @panic("Failure");
    };
    if (controller.primary.master.present) {
        kernel.raw_block_store = &controller.primary.master.block_store_interface;
    }
}
