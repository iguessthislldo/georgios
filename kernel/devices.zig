const memory = @import("memory.zig");
const MemoryError = memory.MemoryError;
const Allocator = memory.Allocator;
const Map = @import("map.zig").Map;

pub const Id = u32;

pub const Device = struct {
    id: Id = undefined,
    deinit_impl: fn(self: *Device) anyerror!void,
    name_impl: fn(self: *Device) []const u8,

    pub fn deinit(self: *Device) anyerror!void {
        try self.deinit_impl(self);
    }

    pub fn name(self: *Device) []const u8 {
        try self.name(self);
    }
};

fn id_eql(a: Id, b: Id) bool {
    return a == b;
}

fn id_cmp(a: Id, b: Id) bool {
    return a > b;
}

pub const Manager = struct {
    const Container = Map(Id, *Device, id_eql, id_cmp);

    alloc: *Allocator = undefined,
    container: Container = undefined,
    next_id: Id = 0,

    pub fn init(self: *Manager, alloc: *Allocator) void {
        self.alloc = alloc;
        self.container = Container{.alloc = alloc};
    }

    pub fn add_device(self: *Manager, device: *Device) MemoryError!void {
        device.id = self.next_id;
        self.next_id += 1;
        _ = try self.container.insert(device.id, device);
    }

    pub fn deinit(self: *Manager) MemoryError!void {
        var it = self.container.iterate();
        while (it.next()) |i| {
            _ = try self.container.remove(i.key);
        }
    }
};
