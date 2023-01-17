// ATA Drive Interface
//
// Also known as Parallel ATA or IDE. This is a simple PIO-based driver.
//
// For Reference See:
//   https://wiki.osdev.org/ATA_PIO_Mode
//   https://en.wikipedia.org/wiki/Parallel_ATA
//   FYSOS: Media Storage Devices https://www.amazon.com/dp/1514111888/

const std = @import("std");

const utils = @import("utils");

const kernel = @import("root").kernel;
const console_writer = kernel.console_writer;
const print = kernel.print;
const io = kernel.io;
const memory = kernel.memory;
const MemoryError = memory.MemoryError;
const Allocator = memory.Allocator;
const devices = kernel.devices;

const pci = @import("pci.zig");
const putil = @import("util.zig");
const timing = @import("timing.zig");

const Error = error {
    FailedToSelectDrive,
    Timeout,
    UnexpectedValues,
    OperationError,
} || MemoryError;

const log_indent = "     ";

const Sector = struct {
    const size: u64 = 512;

    address: u64,
    data: [size]u8 align(8) = undefined,
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

    fn assert_selectable(self: *const CommandStatus) Error!void {
        if (self.busy or self.data_ready) {
            print.format("ERROR: assert_selectable: {}\n", .{self});
            return Error.FailedToSelectDrive;
        }
    }

    // TODO: Make these checks simpler?
    fn drive_is_ready(self: *const CommandStatus) Error!bool {
        if (self.busy) {
            return false;
        }
        if (self.in_error or self.fault) {
            return Error.OperationError;
        }
        return self.drive_ready;
    }

    fn data_is_ready(self: *const CommandStatus) Error!bool {
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
        const raw_bit_size = utils.packed_bit_size(Raw);
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

        fn to_string(self: AddressType) []const u8 {
            return switch (self) {
                .Lba28 => "LBA 28",
                .Lba48 => "LBA 48",
            };
        }
    };

    model: []u8,
    sector_count: u64,
    address_type: AddressType,

    fn from_sector(sector: *Sector) Error!IndentifyResults {
        var results: IndentifyResults = undefined;
        const raw = @ptrCast(*Raw, &sector.data[0]);

        results.model.ptr = @ptrCast([*]u8, &raw.model[0]);
        results.model.len = raw.model.len * 2;
        for (raw.model) |*i| {
            i.* = @byteSwap(u16, i.*);
        }
        results.model.len = utils.stripped_string_size(results.model);
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

    const Device = struct {
        const Id = enum(u1) {
            Master,
            Slave,
        };
        id: Id,
        present: bool = false,
        selected: bool = false,
        alloc: *memory.Allocator = undefined,
        block_store_if: io.BlockStore = undefined,
        sector_count: u64 = 0,
        desc: []const u8 = undefined,
        device_if: devices.Device = undefined,

        fn get_channel(self: *Device) *Channel {
            return if (self.id == .Master) @fieldParentPtr(Channel, "master", self)
                else @fieldParentPtr(Channel, "slave", self);
        }

        fn select(self: *Device) Error!void {
            if (self.selected) return;

            const channel = self.get_channel();

            try channel.read_command_status().assert_selectable();
            channel.write_select(self.id);
            timing.wait_microseconds(1);
            _ = channel.read_command_status();
            try channel.read_command_status().assert_selectable();
            self.selected = true;
            channel.selected(self.id);
        }

        const wait_timeout_ms = 100;

        // TODO: Merge these wait functions?
        fn wait_while_busy(self: *Device) Error!void {
            const channel = self.get_channel();
            var milliseconds_left: u64 = wait_timeout_ms;
            while (channel.read_command_status().busy) {
                milliseconds_left -= 1;
                if (milliseconds_left == 0) {
                    print.string("wait_while_busy Timeout\n");
                    return Error.Timeout;
                }
                timing.wait_milliseconds(1);
            }
        }

        fn wait_for_drive(self: *Device) Error!void {
            const channel = self.get_channel();
            var milliseconds_left: u64 = wait_timeout_ms;
            _ = channel.read_control_status();
            while (!try channel.read_control_status().drive_is_ready()) {
                milliseconds_left -= 1;
                if (milliseconds_left == 0) {
                    print.format("wait_for_drive Timeout {}\n", .{
                        channel.read_control_status()});
                    return Error.Timeout;
                }
                timing.wait_milliseconds(1);
            }
        }

        fn wait_for_data(self: *Device) Error!void {
            const channel = self.get_channel();
            var milliseconds_left: u64 = wait_timeout_ms;
            _ = channel.read_control_status();
            while (!try channel.read_control_status().data_is_ready()) {
                milliseconds_left -= 1;
                if (milliseconds_left == 0) {
                    print.string("wait_for_data Timeout\n");
                    return Error.Timeout;
                }
                timing.wait_milliseconds(1);
            }
        }

        fn reset(self: *Device) Error!void {
            try self.select();

            const channel = self.get_channel();

            // Enable Reset
            channel.write_control(Control{.interrupts_disabled = true, .reset = true});
            // Wait 5+ us
            timing.wait_microseconds(5);

            // Disable Reset
            channel.write_control(Control{.interrupts_disabled = true, .reset = false});
            // Wait 2+ ms
            timing.wait_milliseconds(2);

            // Wait for controller to stop being busy
            try self.wait_while_busy();
            // Wait 5+ ms
            timing.wait_milliseconds(5);
            _ = channel.read_error();

            // Read Expected Values
            try channel.check_sector_registers();
            print.format(log_indent ++ "    - type: {:x}\n", .{channel.read_cylinder()});
        }

        fn dev_deinit_impl(device: *devices.Device) void {
            _ = device;
            const self = @fieldParentPtr(Device, "device_if", device);
            const std_alloc = self.alloc.std_allocator();
            std_alloc.free(self.desc);
            // TODO: Make sure disk is done writing? Make sure nothing is using
            // the disk?
        }

        fn dev_desc_impl(device: *devices.Device) []const u8 {
            const self = @fieldParentPtr(Device, "device_if", device);
            return self.desc;
        }

        fn as_block_store_impl(device: *devices.Device) *io.BlockStore {
            const self = @fieldParentPtr(Device, "device_if", device);
            return &self.block_store_if;
        }

        fn init(self: *Device, controller_dev: *devices.Device,
                temp_sector: *Sector, alloc: *memory.Allocator) Error!void {
            print.format(log_indent ++ "  - {}\n", .{self.id});
            const channel = self.get_channel();
            self.alloc = alloc;

            try self.reset();

            try self.wait_for_drive();
            channel.identify_command();
            _ = channel.read_command_status();
            try self.wait_for_data();
            channel.read_sector(temp_sector);
            const identity = try IndentifyResults.from_sector(temp_sector);
            const total_size = std.fmt.fmtIntSizeBin(identity.sector_count * Sector.size);
            try console_writer.print(
                log_indent ++ "    - Drive Model: \"{s}\"\n" ++
                log_indent ++ "    - Address Type: {s}\n" ++
                log_indent ++ "    - Sector Count: {}\n" ++
                log_indent ++ "    - Total Size: {}\n",
                .{
                    identity.model,
                    identity.address_type.to_string(),
                    identity.sector_count,
                    total_size,
                }
            );

            self.present = true;
            self.sector_count = identity.sector_count;
            self.block_store_if = .{
                .page_alloc = kernel.big_alloc.std_allocator(),
                .block_size = Sector.size,
                .max_address = identity.sector_count,
                .read_block_impl = Device.read_block,
                .write_block_impl = Device.write_block,
            };

            self.device_if = .{
                .class = .Disk,
                .deinit_impl = dev_deinit_impl,
                .desc_impl = dev_desc_impl,
                .as_block_store_impl = as_block_store_impl
            };
            var sw = utils.StringWriter.init(alloc.std_allocator());
            try sw.writer().print("{} ATA Disk \"{s}\"", .{total_size, identity.model});
            self.desc = sw.get();
            try controller_dev.add_child_device(&self.device_if, "disk");
        }

        fn read_write_common(self: *Device, address: u64) Error!*Channel {
            if (address >= self.sector_count) {
                print.format("ATA: read address {} is too large for {} sector device\n",
                    .{address, self.sector_count});
                return Error.OperationError;
            }
            try self.select();
            const channel = self.get_channel();
            try self.wait_for_drive();
            channel.write_lba48(self.id, address, 1);
            timing.wait_microseconds(5);
            return channel;
        }

        fn read_impl(self: *Device, address: u64, data: []u8) Error!void {
            const channel = try self.read_write_common(address);
            channel.read_sectors_command();
            _ = channel.read_command_status();
            const error_reg = channel.read_error();
            const status_reg = channel.read_command_status();
            if (((error_reg & 0x80) != 0) or status_reg.in_error or status_reg.fault) {
                print.string("ATA Read Error\n");
                return Error.OperationError;
            }
            try self.wait_for_data();
            channel.read_sector_impl(data);
        }

        fn read_sector(self: *Device, sector: *Sector) Error!void {
            try self.read_impl(sector.address, sector.data[0..]);
        }

        fn read_block(block_store: *io.BlockStore, block: *io.Block) io.FileError!void {
            const self = @fieldParentPtr(Device, "block_store_if", block_store);
            if (block.data == null) return io.FileError.NotEnoughDestination;
            self.read_impl(block.address, block.data.?[0..])
                catch return io.FileError.Internal;
        }

        fn write_impl(self: *Device, address: u64, data: []const u8) Error!void {
            const channel = self.read_write_common(address) catch |e| {
                print.format("read_write_common failed: {}\n", .{@errorName(e)});
                return e;
            };

            channel.write_sectors_command();
            _ = channel.read_command_status();
            const error_reg = channel.read_error();
            const status_reg = channel.read_command_status();
            if (((error_reg & 0x80) != 0) or status_reg.in_error or status_reg.fault) {
                print.string("ATA Write Error\n");
                return Error.OperationError;
            }

            self.wait_for_data() catch |e| {
                print.format("wait_for_data failed: {}\n", .{@errorName(e)});
                return e;
            };

            channel.write_sector_impl(data);
            channel.flush_command(); // TODO: Lunt says this isn't needed everytime
            self.wait_while_busy() catch |e| {
                print.format("wait_while_busy failed: {}\n", .{@errorName(e)});
                return e;
            };
        }

        fn write_block(block_store: *io.BlockStore, block: *io.Block) io.FileError!void {
            const self = @fieldParentPtr(Device, "block_store_if", block_store);
            if (block.data == null) return io.FileError.NotEnoughSource;
            self.write_impl(block.address, block.data.?[0..]) catch return io.FileError.Internal;
        }
    };

    const Channel = struct {
        const Id = enum(u1) {
            Primary,
            Secondary,
        };

        id: Id,
        io_base_port: u16,
        pio_data_port: u16 = 0,
        error_port: u16 = 1,
        sector_count_port: u16 = 2,
        lba_low_port: u16 = 3, // AKA sector number
        lba_mid_port: u16 = 4, // AKA cylinder low
        lba_high_port: u16 = 5, // AKA cylinder high
        drive_head_port: u16 = 6,
        command_port: u16 = 7,
        control_base_port: u16,
        irq: u8,
        master: Device = Device{.id = .Master},
        slave: Device = Device{.id = .Slave},

        fn init(self: *Channel,
                controller_dev: *devices.Device, temp_sector: *Sector, alloc: *Allocator) void {
            self.pio_data_port += self.io_base_port;
            self.error_port += self.io_base_port;
            self.sector_count_port += self.io_base_port;
            self.lba_low_port += self.io_base_port;
            self.lba_mid_port += self.io_base_port;
            self.lba_high_port += self.io_base_port;
            self.drive_head_port += self.io_base_port;
            self.command_port += self.io_base_port;

            print.format(log_indent ++ "- {}\n", .{self.id});
            self.master.init(controller_dev, temp_sector, alloc) catch {
                print.string(log_indent ++ "  - Master Failed\n");
            };
            self.slave.init(controller_dev, temp_sector, alloc) catch {
                print.string(log_indent ++ "  - Slave Failed\n");
            };
        }

        fn selected(self: *Channel, id: Device.Id) void {
            if (id == Device.Id.Master) {
                self.slave.selected = false;
            } else {
                self.master.selected = false;
            }
        }

        fn read_command_status(self: *Channel) CommandStatus {
            return @bitCast(CommandStatus, putil.in8(self.command_port));
        }

        fn read_control_status(self: *Channel) CommandStatus {
            return @bitCast(CommandStatus, putil.in8(self.control_base_port + 2));
        }

        fn read_error(self: *Channel) u8 { // TODO: Create Struct?
            return putil.in8(self.error_port);
        }

        fn check_sector_registers(self: *Channel) Error!void {
            const sector_count = putil.in8(self.sector_count_port);
            const sector_number = putil.in8(self.lba_low_port);
            if (sector_count != 1 and sector_number != 1) {
                print.format(log_indent ++ "    - reset: expected 1, 1 for sector count "
                    ++ "and number, but got {}, {}\n", .{sector_count, sector_number});
                return Error.UnexpectedValues;
            }
        }

        fn read_cylinder(self: *Channel) u16 {
            const low = @intCast(u16, putil.in8(self.lba_mid_port));
            const high = @intCast(u16, putil.in8(self.lba_high_port));
            return (high << 8) | low;
        }

        fn write_drive_head_select(self: *Channel, value: DriveHeadSelect) void {
            putil.out8(self.drive_head_port, @bitCast(u8, value));
        }

        fn write_select(self: *Channel, value: Device.Id) void {
            self.write_drive_head_select(
                DriveHeadSelect{.select_slave = value == Device.Id.Slave});
        }

        fn out8(port: u16, value: anytype) void {
            putil.out8(port, @truncate(u8, value));
        }

        fn write_lba48(self: *Channel,
                device: Device.Id, lba: u64, sector_count: u16) void {
            out8(self.sector_count_port, sector_count >> 8);
            out8(self.lba_low_port, lba >> 24);
            out8(self.lba_mid_port, lba >> 32);
            out8(self.lba_high_port, lba >> 40);
            out8(self.sector_count_port, sector_count);
            out8(self.lba_low_port, lba);
            out8(self.lba_mid_port, lba >> 8);
            out8(self.lba_high_port, lba >> 16);
            self.write_drive_head_select(DriveHeadSelect{
                .lba = true,
                .select_slave = device == Device.Id.Slave,
            });
        }

        fn read_sectors_command(self: *const Channel) void {
            putil.out8(self.command_port, 0x24);
        }

        fn write_sectors_command(self: *const Channel) void {
            putil.out8(self.command_port, 0x34);
        }

        fn flush_command(self: *const Channel) void {
            putil.out8(self.command_port, 0xe7);
        }

        fn identify_command(self: *const Channel) void {
            putil.out8(self.io_base_port + 7, 0xEC);
        }

        fn write_control(self: *Channel, value: Control) void {
            putil.out8(self.control_base_port + 2, @bitCast(u8, value));
        }

        fn read_sector(self: *Channel, sector: *Sector) void {
            self.read_sector_impl(sector.data[0..]);
        }

        fn read_sector_impl(self: *Channel, data: []u8) void {
            putil.in_bytes(self.pio_data_port, data);
        }

        fn write_sector_impl(self: *Channel, data: []const u8) void {
            for (std.mem.bytesAsSlice(u16, data)) |word| {
                putil.out16(self.pio_data_port, word);
            }
        }
    };

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
    device_if: devices.Device = undefined,
    alloc: *Allocator = undefined,

    fn init(self: *Controller, alloc: *Allocator) void {
        self.alloc = alloc;
        self.device_if = .{
            .class = .Bus,
            .deinit_impl = deinit_impl,
        };

        // Make sure this is Triton II controller emulated by QEMU
        // if (header.vendor_id != 0x8086 or header.device_id != 0x7010 or
        //         header.prog_if != 0x80) {
        //     print.string(log_indent ++ "- Unknown IDE Controller\n");
        //     return;
        // }
    }

    fn init_disks(self: *Controller) void {
        const temp_sector = self.alloc.alloc(Sector) catch {
            print.string("ERROR: Failed to allocate sector for ATA initialization\n");
            return;
        };
        defer self.alloc.free(temp_sector) catch unreachable;

        self.primary.init(&self.device_if, temp_sector, self.alloc);
        self.secondary.init(&self.device_if, temp_sector, self.alloc);
    }

    fn deinit_impl(device: *devices.Device) void {
        const self = @fieldParentPtr(Controller, "device_if", device);
        // TODO: Make sure disks can be safely stop being used.
        self.alloc.free(self) catch unreachable;
    }
};

pub fn init(dev: *const pci.Dev) void {
    _ = dev;
    var controller = kernel.alloc.alloc(Controller) catch {
        @panic("Failure");
    };
    controller.* = .{};
    controller.init(kernel.alloc);
    kernel.device_mgr.root_device.add_child_device(&controller.device_if, "ata") catch {
        @panic("Failure");
    };
    controller.init_disks();
}
