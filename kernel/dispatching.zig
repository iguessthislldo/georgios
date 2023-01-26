// ===========================================================================
// Dispatching Ports and Interfaces
// ===========================================================================
//
// Dispatching is the planned future method for IPC and generally how programs
// will talk to the OS. The lowest layer of this are ports for passing bytes in
// messages called a Dispatch to and from abstract places. Interfaces in OMG
// IDL are used to generate abstract structs in Zig with helper code to pass
// parameters of the abstract methods using a port. This can then interact
// directly with kernel code. This should be somewhat easier then implementing
// system calls using the current method.
//
// Later this should also be able to be used to communicate with other
// threads and processes using queued messages. Accessing interfaces will
// be done through the file system where objects (could be files or
// directories) will present multiple possible interfaces. Current
// influences for all this are Mach ports and to a lesser extend Fuchsia
// interfaces and Plan 9 Styx.

const std = @import("std");
const Allocator = std.mem.Allocator;

const utils = @import("utils");
const georgios = @import("georgios");
pub const Error = georgios.DispatchError;
pub const PortId = georgios.PortId;
pub const Dispatch = georgios.Dispatch;
pub const SendOpts = georgios.SendOpts;
pub const RecvOpts = georgios.RecvOpts;
pub const CallOpts = georgios.CallOpts;

const kernel = @import("kernel.zig");
const console_writer = kernel.console_writer;
const MemoryError = kernel.memory.MemoryError;
const threading = kernel.threading;
const Process = threading.Process;

pub const Port = struct {
    send_impl: ?fn(port: *Port, dispatch: Dispatch, opts: SendOpts) Error!void = null,
    recv_impl: ?fn(port: *Port, src: PortId, opts: RecvOpts) Error!?Dispatch = null,
    call_impl: ?fn(self: *Port, dispatch: Dispatch, opts: CallOpts) Error!Dispatch = null,
    close_impl: ?fn(self: *Port) void,

    pub fn send(self: *Port, dispatch: Dispatch, opts: SendOpts) Error!void {
        if (self.send_impl) |send_impl| {
            return send_impl(self, dispatch, opts);
        }
        return Error.DispatchOpUnsupported;
    }

    pub fn recv(self: *Port, src: PortId, opts: RecvOpts) Error!?Dispatch {
        if (self.recv_impl) |recv_impl| {
            return recv_impl(self, src, opts);
        }
        return Error.DispatchOpUnsupported;
    }

    pub fn call(self: *Port, dispatch: Dispatch, opts: CallOpts) Error!Dispatch {
        if (self.call_impl) |call_impl| {
            return call_impl(self, dispatch, opts);
        }
        return Error.DispatchOpUnsupported;
    }

    pub fn close(self: *Port) void {
        return self.close_impl(self);
    }
};

pub const Dispatcher = struct {
    const Ports = std.AutoHashMap(PortId, *Port);

    alloc: Allocator,
    process: *Process,
    next_id: PortId = georgios.FirstDynamicPort,
    ports: Ports,
    meta_port: Port,
    directory: georgios.Directory, // TODO: Temporarily connected to meta port

    pub fn init(self: *Dispatcher, alloc: Allocator, process: *Process) MemoryError!void {
        self.* = .{
            .alloc = alloc,
            .process = process,
            .ports = Ports.init(alloc),
            .meta_port = .{
                .send_impl = meta_port_send_impl,
                .close_impl = meta_port_close_impl,
            },
            .directory = .{
                ._port_id = georgios.MetaPort,
                ._create_impl = create_impl,
                ._unlink_impl = unlink_impl,
            },
        };
        try self.map_port_to(&self.meta_port, georgios.MetaPort);
    }

    fn map_port_to(self: *Dispatcher, port: *Port, id: PortId) MemoryError!void {
        try self.ports.putNoClobber(id, port);
    }

    pub fn map_port(self: *Dispatcher, port: *Port) Error!PortId {
        const id = self.next_id;
        try self.map_port_to(port, id);
        self.next_id += 1;
        return id;
    }

    fn get_port(self: *Dispatcher, id: PortId) Error!*Port {
        return self.ports.get(id) orelse Error.DispatchInvalidPort;
    }

    // TODO: Remove
    pub fn create_impl(dir: *georgios.Directory, path: []const u8, kind: georgios.fs.NodeKind) georgios.DispatchError!void {
        const self = @fieldParentPtr(Dispatcher, "directory", dir);
        _ = self;
        try console_writer.print("create_impl({s}) called\n", .{path});
        if (kernel.threading_mgr.current_process) |p| {
            p.fs_submgr.create(path, kind) catch |e| {
                try console_writer.print("create_impl error: {s}\n", .{@errorName(e)});
            };
        }
    }

    // TODO: Remove
    pub fn unlink_impl(dir: *georgios.Directory, path: []const u8) georgios.DispatchError!void {
        const self = @fieldParentPtr(Dispatcher, "directory", dir);
        _ = self;
        try console_writer.print("unlink_impl({s}) called\n", .{path});
        if (kernel.threading_mgr.current_process) |p| {
            p.fs_submgr.unlink(path) catch |e| {
                try console_writer.print("unlink_impl error: {s}\n", .{@errorName(e)});
            };
        }
    }

    fn meta_port_send_impl(port: *Port, dispatch: Dispatch, opts: SendOpts) Error!void {
        const self = @fieldParentPtr(Dispatcher, "meta_port", port);
        _ = opts;
        try self.directory._recv_value(dispatch);
    }

    fn meta_port_close_impl(port: *Port) void {
        _ = port;
        // Closing the met-aport doesn't do anything...
    }

    pub fn send(self: *Dispatcher, dispatch: Dispatch, opts: SendOpts) Error!void {
        try (try self.get_port(dispatch.dst)).send(dispatch, opts);
    }

    pub fn recv(self: *Dispatcher, src: PortId, opts: RecvOpts) Error!?Dispatch {
        return (try self.get_port(src)).recv(src, opts); // src or dst, or both?
    }

    pub fn call(self: *Dispatcher, dispatch: Dispatch, opts: CallOpts) Error!Dispatch {
        return (try self.get_port(dispatch.dst)).call(dispatch, opts);
    }
};
