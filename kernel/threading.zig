const pthreading = @import("platform.zig").impl.threading;
const Kernel = @import("kernel.zig").Kernel;
const memory = @import("memory.zig");
const util = @import("util.zig");

const Error = pthreading.Error;

pub const Thread = struct {
    const Id = u32;

    id: Id = undefined,
    kernel_thread: bool = false,
    impl: pthreading.ThreadImpl = pthreading.ThreadImpl{},
    process: ?*Process = null,
    prev_in_system: ?*Thread = null,
    next_in_system: ?*Thread = null,

    pub fn init(self: *Thread, memory_manger: *memory.Memory) Error!void {
        try self.impl.init(self, memory_manger);
    }

    pub fn start(self: *Thread) Error!void {
        try self.impl.start();
    }
};

pub const Process = struct {
    const Id = u32;

    memory_manager: *memory.Memory = undefined,
    id: Id = undefined,
    impl: pthreading.ProcessImpl = undefined,
    main_thread: Thread = Thread{},
    entry: usize = 0,

    pub fn init(self: *Process, memory_manager: *memory.Memory) Error!void {
        self.memory_manager = memory_manager;
        self.impl = pthreading.ProcessImpl{.process = self};
        try self.impl.init(self);
        try self.main_thread.init(memory_manager);
    }

    pub fn start(self: *Process) Error!void {
        try self.impl.start();
    }

    pub fn address_space_copy(self: *Process,
            address: usize, data: []const u8) memory.AllocError!void {
        try self.impl.address_space_copy(address, data);
    }

    pub fn address_space_set(self: *Process,
            address: usize, byte: u8, len: usize) memory.AllocError!void {
        try self.impl.address_space_set(address, byte, len);
    }
};

pub const Manager = struct {
    memory_manager: *memory.Memory,
    head_thread: ?*Thread = null,
    tail_thread: ?*Thread = null,

    pub fn new_process(self: *Manager) Error!*Process {
        const p = try self.memory_manager.small_alloc.alloc(Process);
        p.* = Process{};
        try p.init(self.memory_manager);
        return p;
    }

    pub fn start_process(self: *Manager, process: *Process) Error!void {
        self.insert_thread(&process.main_thread);
        try process.start();
    }

    pub fn insert_thread(self: *Manager, thread: *Thread) void {
        if (self.tail_thread) |tail| {
            tail.next_in_system = thread;
            thread.prev_in_system = tail;
            self.tail_thread = thread;
        }
        if (self.head_thread == null) {
            self.head_thread = thread;
            self.tail_thread = thread;
        }
    }
};
