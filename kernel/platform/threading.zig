const std = @import("std");

const kthreading = @import("../threading.zig");
const Thread = kthreading.Thread;
const Process = kthreading.Process;
const kutil = @import("../util.zig");
const kmemory = @import("../memory.zig");
const Range = kmemory.Range;

const platform = @import("platform.zig");
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

    fn push_to_context(self: *ThreadImpl, value: anytype) void {
        const Type = @TypeOf(value);
        const size = @sizeOf(Type);
        self.context -= size;
        _ = kutil.memory_copy_truncate(
            @intToPtr([*]u8, self.context)[0..size], std.mem.asBytes(&value));
    }

    fn pop_from_context(self: *ThreadImpl, comptime Type: type) Type {
        const size = @sizeOf(Type);
        var value: Type = undefined;
        _ = kutil.memory_copy_truncate(
            std.mem.asBytes(&value), @intToPtr([*]const u8, self.context)[0..size]);
        self.context += size;
        return value;
    }

    fn return_to() callconv(.Naked) noreturn {
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

    pub fn start(self: *ThreadImpl) Error!void {
        // TODO: Real Context Switch
        _ = self.pop_from_context(usize);
        const is = self.pop_from_context(InterruptStack);
        usermode(is.eip, is.esp);
    }
};

pub const ProcessImpl = struct {
    process: *Process,
    page_directory: []u32 = undefined,

    pub inline fn kmem(self: *ProcessImpl) *kmemory.Memory {
        return self.process.memory_manager;
    }

    pub inline fn pmem(self: *ProcessImpl) *pmemory.Memory {
        return &self.kmem().platform_memory;
    }

    pub fn init(self: *ProcessImpl, process: *Process) Error!void {
        self.process = process;
        self.page_directory = try self.pmem().new_page_directory();
    }

    pub fn start(self: *ProcessImpl) Error!void {
        const usermode_stack = Range{
            .start = platform.kernel_to_virtual(0) - platform.frame_size,
            .size = platform.frame_size};
        try self.pmem().mark_virtual_memory_present(
            self.page_directory, usermode_stack, true);
        const kernelmode_stack = try self.kmem().big_alloc.alloc_range(kutil.Ki(4));
        platform.segments.set_usermode_interrupt_stack(kernelmode_stack.end() - 1);
        try pmemory.load_page_directory(self.page_directory, null);
        self.process.main_thread.impl.setup_context(
            usermode_stack.end() - 1, self.process.entry);
        try self.process.main_thread.start();
    }

    pub fn address_space_copy(self: *ProcessImpl,
            address: usize, data: []const u8) kmemory.AllocError!void {
        try self.pmem().page_directory_memory_copy(self.page_directory, address, data);
    }

    pub fn address_space_set(self: *ProcessImpl,
            address: usize, byte: u8, len: usize) kmemory.AllocError!void {
        try self.pmem().page_directory_memory_set(self.page_directory, address, byte, len);
    }
};
