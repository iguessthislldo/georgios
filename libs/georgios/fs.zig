// Generated from libs/georgios/fs.idl by ifgen.py

const georgios = @import("georgios.zig");

pub const Directory = struct {
    pub fn create(self: *Directory, path: []const u8, kind: georgios.fs.NodeKind) georgios.DispatchError!void {
        return self._create_impl(self, path, kind);
    }

    pub fn unlink(self: *Directory, path: []const u8) georgios.DispatchError!void {
        return self._unlink_impl(self, path);
    }

    pub const _ArgVals = union (enum) {
        _create: struct {
            path: []const u8,
            kind: georgios.fs.NodeKind,
        },
        _unlink: []const u8,
    };

    pub const _RetVals = union (enum) {
        _create: void,
        _unlink: void,
    };

    pub const _dispatch_impls = struct {
        pub fn _create_impl(self: *Directory, path: []const u8, kind: georgios.fs.NodeKind) georgios.DispatchError!void {
            return georgios.send_value(&_ArgVals{._create = .{.path = path, .kind = kind}}, self._port_id, .{});
        }

        pub fn _unlink_impl(self: *Directory, path: []const u8) georgios.DispatchError!void {
            return georgios.send_value(&_ArgVals{._unlink = path}, self._port_id, .{});
        }
    };

    pub fn _recv_value(self: *Directory, dispatch: georgios.Dispatch) georgios.DispatchError!void {
        return switch ((try georgios.msg_cast(_ArgVals, dispatch)).*) {
            ._create => |val| self._create_impl(self, val.path, val.kind),
            ._unlink => |val| self._unlink_impl(self, val),
        };
    }

    _port_id: georgios.PortId,
    _create_impl: fn(self: *Directory, path: []const u8, kind: georgios.fs.NodeKind) georgios.DispatchError!void = _dispatch_impls._create_impl,
    _unlink_impl: fn(self: *Directory, path: []const u8) georgios.DispatchError!void = _dispatch_impls._unlink_impl,
};
