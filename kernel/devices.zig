const std = @import("std");
const Allocator = std.mem.Allocator;

const utils = @import("utils");

const kernel = @import("kernel.zig");
const BlockStore = kernel.io.BlockStore;

pub const Error = Allocator.Error;

pub const Class = enum (u32) {
    Unknown,
    Root,
    Other,
    Bus,
    Disk,

    const strings = [@typeInfo(Class).Enum.fields.len][]const u8{
        "unknown",
        "device root",
        "other",
        "bus",
        "disk",
    };

    pub fn to_string(self: Class) []const u8 {
        return strings[@enumToInt(self)];
    }
};

pub const Id = u32;

pub const Device = struct {
    const ChildDevices = std.StringHashMap(*Device);

    class: Class,
    deinit_impl: fn(self: *Device) void,
    desc_impl: ?fn(self: *Device) []const u8 = null,
    as_block_store_impl: ?fn(self: *Device) *BlockStore = null,

    alloc: Allocator = undefined,
    id: Id = undefined,
    name: []const u8 = undefined,
    child_devices: ChildDevices = undefined,
    next_child_id: Id = 0,

    pub fn init(self: *Device, alloc: Allocator, id: Id) void {
        self.alloc = alloc;
        self.id = id;
        self.child_devices = ChildDevices.init(alloc);
    }

    pub fn deinit(self: *Device) void {
        var it = self.devices.iterator();
        while (it.next()) |kv| {
            kv.value_ptr.deinit() catch unreachable;
        }
        self.devices.deinit();
        self.deinit_impl(self);
        self.alloc.free(self.name);
    }

    pub fn desc(self: *Device) ?[]const u8 {
        if (self.desc_impl) |desc_impl| {
            return desc_impl(self);
        }
        return null;
    }

    pub fn add_child_device(self: *Device, device: *Device, prefix: []const u8) Error!void {
        device.init(self.alloc, self.next_child_id);
        var sw = utils.StringWriter.init(self.alloc);
        try sw.writer().print("{s}{}", .{prefix, device.id});
        device.name = sw.get();
        self.next_child_id += 1;
        try self.child_devices.putNoClobber(device.name, device);
    }

    pub fn get(self: *Device, path: []const []const u8) ?*Device {
        if (path.len > 0) {
            if (self.child_devices.get(path[0])) |child| {
                return child.get(path[1..]);
            }
            return null;
        }
        return self;
    }

    pub fn print(self: *Device, writer: anytype, depth: usize) anyerror!void {
        if (depth > 0) {
            const d = depth - 1;
            var i: usize = 0;
            while (i < d) {
                try writer.print("  ", .{});
                i += 1;
            }

            try writer.print("{}: {s}: {s}", .{self.id, self.class.to_string(), self.name});
            if (self.desc()) |descr| {
                try writer.print(": {s}", .{descr});
            }
            try writer.print("\n", .{});
        }
        var it = self.child_devices.iterator();
        while (it.next()) |kv| {
            try kv.value_ptr.*.print(writer, depth + 1);
        }
    }

    pub fn as_block_store(self: *Device) ?*BlockStore {
        if (self.as_block_store_impl) |as_block_store_impl| {
            return as_block_store_impl(self);
        }
        return null;
    }
};

pub const Manager = struct {
    root_device: Device = .{
        .class = .Root,
        .deinit_impl = root_deinit_impl,
    },

    pub fn init(self: *Manager, alloc: Allocator) void {
        self.root_device.init(alloc, undefined);
    }

    pub fn deinit(self: *Manager) void {
        self.root_device.deinit();
    }

    pub fn get(self: *Manager, path: []const []const u8) ?*Device {
        return self.root_device.get(path);
    }

    pub fn print_tree(self: *Manager, writer: anytype) anyerror!void {
        try self.root_device.print(writer, 0);
    }

    fn root_deinit_impl(device: *Device) void {
        _ = device;
    }
};
