const kthreading = @import("../threading.zig");
const Thread = kthreading.Thread;
const Process = kthreading.Process;
const kutil = @import("../util.zig");
const kmemory = @import("../memory.zig");
const Range = kmemory.Range;

const pmemory = @import("memory.zig");
const interrupts = @import("interrupts.zig");
const InterruptStack = interrupts.InterruptStack;

pub const Error = kutil.Error || kmemory.MemoryError;

pub extern fn setup_process(usermode: bool, ip: u32, sp: u32) u32;
pub extern fn context_switch(old: u32, new: u32) void;
pub extern fn usermode(ip: u32, sp: u32) noreturn;

pub const ThreadImpl = struct {
    thread: *Thread = undefined,
    context: usize = undefined,

    pub fn init(self: *ThreadImpl,
            thread: *Thread, memory_manger: *kmemory.Memory) Error!void {
        self.thread = thread;
    }

    fn push_to_context(self: *ThreadImpl, value: var) void {
        const Type = @typeOf(value);
        self.context -= @sizeOf(Type);
        @intToPtr(*Type, self.context).* = value;
    }

    fn pop_from_context(self: *ThreadImpl, Type: type) Type {
        defer self.context -= @sizeOf(Type);
        return @intToPtr(*Type, self.context).*;
    }

    nakedcc fn return_to() noreturn {
        asm volatile (
            \\popal
            \\iret
            );
        unreachable;
    }

    fn setup_context(self: *ThreadImpl, sp: usize, ip: usize) void {
        self.context = sp;
        var is = kutil.zero_init(InterruptStack);
        is.eip = ip;
        is.esp = sp;
        self.push_to_context(is);
        self.push_to_context(@ptrToInt(return_to));
    }

    fn start(self: *ThreadImpl) Error!void {
    }
};

pub const ProcessImpl = struct {
    process: *Process,
    page_directory: []u32 = undefined,

    pub inline fn mem(self: *ProcessImpl) *pmemory.Memory {
        return &self.process.memory_manager.platform_memory;
    }

    pub fn init(self: *ProcessImpl, process: *Process) Error!void {
        self.process = process;
        self.page_directory = try self.mem().new_page_directory();
    }

    pub fn start(self: *ProcessImpl) Error!void {
        try pmemory.load_page_directory(self.page_directory, null);
        try self.process.main_thread.start();
    }

    pub fn address_space_copy(self: *ProcessImpl,
            address: usize, data: []const u8) kmemory.AllocError!void {
        try self.mem().page_directory_memory_copy(self.page_directory, address, data);
    }

    pub fn address_space_set(self: *ProcessImpl,
            address: usize, byte: u8, len: usize) kmemory.AllocError!void {
        try self.mem().page_directory_memory_set(self.page_directory, address, byte, len);
    }
};
