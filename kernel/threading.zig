const platform = @import("platform.zig");
const pthreading = platform.impl.threading;
const kernel = @import("kernel.zig");
const memory = @import("memory.zig");
const util = @import("util.zig");
const print = @import("print.zig");

const Error = pthreading.Error;

pub const Thread = struct {
    const Id = u32;

    id: Id = undefined,
    kernel_mode: bool = false,
    impl: pthreading.ThreadImpl = undefined,
    process: ?*Process = null,
    prev_in_system: ?*Thread = null,
    next_in_system: ?*Thread = null,
    entry: usize = 0,

    pub fn init(self: *Thread, boot_thread: bool) Error!void {
        if (self.process) |process| {
            self.kernel_mode = process.kernel_mode;
        }
        try self.impl.init(self, boot_thread);
    }

    pub fn start(self: *Thread) Error!void {
        try self.impl.start();
    }
};

pub const Process = struct {
    const Id = u32;

    id: Id = undefined,
    kernel_mode: bool = false,
    impl: pthreading.ProcessImpl = undefined,
    main_thread: Thread = Thread{},
    entry: usize = 0,

    pub fn init(self: *Process) Error!void {
        try self.impl.init(self);
        self.main_thread.process = self;
        try self.main_thread.init(false);
    }

    pub fn start(self: *Process) Error!void {
        self.main_thread.entry = self.entry;
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
    head_thread: ?*Thread = null,
    tail_thread: ?*Thread = null,
    next_thread_id: Thread.Id = 0,
    current_process: ?*Process = null,
    current_thread: ?*Thread = null,
    boot_thread: Thread = .{.id = 0, .kernel_mode = true},

    pub fn init(self: *Manager) Error!void {
        try self.boot_thread.init(true);
        self.current_thread = &self.boot_thread;
        platform.disable_interrupts();
        self.insert_thread(&self.boot_thread);
        platform.enable_interrupts();
    }

    pub fn new_process(self: *Manager, kernel_mode: bool) Error!*Process {
        const p = try kernel.memory.small_alloc.alloc(Process);
        p.* = Process{.kernel_mode = kernel_mode};
        try p.init();
        return p;
    }

    pub fn start_process(self: *Manager, process: *Process) Error!void {
        platform.disable_interrupts();
        self.insert_thread(&process.main_thread);
        try process.start();
    }

    pub fn insert_thread(self: *Manager, thread: *Thread) void {
        // Assign ID
        thread.id = self.next_thread_id;
        self.next_thread_id += 1;

        // Insert into Thread List
        if (self.head_thread == null) {
            self.head_thread = thread;
        }
        if (self.tail_thread) |tail| {
            tail.next_in_system = thread;
        }
        thread.prev_in_system = self.tail_thread;
        thread.next_in_system = null;
        self.tail_thread = thread;
    }

    pub fn remove_thread(self: *Manager, thread: *Thread) void {
        if (thread.next_in_system) |nt| {
            nt.prev_in_system = thread.prev_in_system;
        }
        if (thread.prev_in_system) |pt| {
            pt.next_in_system = thread.next_in_system;
        }
        if (self.head_thread == thread) {
            self.head_thread = thread.next_in_system;
        }
        if (self.tail_thread == thread) {
            self.tail_thread = thread.prev_in_system;
        }
    }

    pub fn remove_current_thread(self: *Manager) void {
        platform.disable_interrupts();
        if (self.current_thread) |thread| {
            print.format("Thread {} has Finished\n", .{thread.id});
            self.remove_thread(thread);
            // TODO: Cleanup Process, Memory
            while (true) {
                self.yield();
            }
        } else {
            @panic("remove_current_thread: no current thread");
        }
        @panic("remove_current_thread: reached end");
    }

    fn next_from(self: *const Manager, thread_maybe: ?*Thread) ?*Thread {
        var next_thread: ?*Thread = null;
        if (thread_maybe) |thread| {
            next_thread = thread.next_in_system;
            if (next_thread == null) {
                next_thread = self.head_thread;
            }
            if (next_thread != null and next_thread.? == thread) {
                next_thread = null;
            }
        }
        if (next_thread) |nt| {
            print.format("({})", .{nt.id});
        } else {
            print.string("(null)");
        }
        return next_thread;
    }

    pub fn next(self: *Manager) ?*Thread {
        return self.next_from(self.current_thread);
    }

    pub fn yield(self: *Manager) void {
        platform.disable_interrupts();
        if (self.next()) |next_thread| {
            next_thread.impl.switch_to();
        }
    }
};
