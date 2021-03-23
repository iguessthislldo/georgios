const std = @import("std");

const kernel = @import("../kernel.zig");
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

    const SwitchToFrame = packed struct {
        // pushf
        eflags: u32,
        // pusha
        edi: u32,
        esi: u32,
        ebp: u32,
        esp: u32,
        ebx: u32,
        edx: u32,
        ecx: u32,
        eax: u32,
        // Function
        func_value1: u32,
        func_value0: u32,
        func_ebx: u32,
        func_ebp: u32,
        func_return: u32,
    };

    fn setup_context(self: *ThreadImpl, sp: usize, ip: usize) void {
        self.context = sp;
        var frame = kutil.zero_init(SwitchToFrame);
        frame.esp = sp;
        frame.func_return = ip;
        frame.func_ebp = sp;
        self.push_to_context(frame);
    }

    pub fn prepare_for_switch_to(self: *ThreadImpl) void {
        if (self.thread.process) |process| {
            process.impl.switch_to() catch @panic("ProcessImpl.switch_to");
        }
        kernel.kernel.threading_manager.current_process = self.thread.process;
    }

    pub fn switch_to(self: *ThreadImpl) void {
        // WARNING: A FRAME FOR THIS FUNCTION NEEDS TO BE SETUP IN setup_context!
        const last = kernel.kernel.threading_manager.current;
        kernel.kernel.threading_manager.current = self.thread;
        self.prepare_for_switch_to();
        asm volatile (
            \\pusha
            \\pushf
            \\movl %%esp, (%[old_context_ptr])
            \\movl %[new_context], %%esp
            \\popf
            \\popa
            : :
                [old_context_ptr] "{ax}" (@ptrToInt(&last.impl.context)),
                [new_context] "{bx}" (self.context));
    }
};

pub const ProcessImpl = struct {
    process: *Process,
    page_directory: []u32,
    usermode_stack: Range,
    kernelmode_stack: Range,
    main_thread_is_setup: bool,

    pub inline fn kmem(self: *ProcessImpl) *kmemory.Memory {
        return self.process.memory_manager;
    }

    pub inline fn pmem(self: *ProcessImpl) *pmemory.Memory {
        return &self.kmem().platform_memory;
    }

    pub fn init(self: *ProcessImpl, process: *Process) Error!void {
        self.process = process;
        self.page_directory = try self.pmem().new_page_directory();
        if (!process.kernel_mode) {
            self.usermode_stack = Range{
                .start = platform.kernel_to_virtual(0) - platform.frame_size,
                .size = platform.frame_size};
            try self.pmem().mark_virtual_memory_present(
                self.page_directory, self.usermode_stack, true);
        }
        self.kernelmode_stack = try self.kmem().big_alloc.alloc_range(kutil.Ki(4));
        self.main_thread_is_setup = false;
    }

    pub fn switch_to(self: *ProcessImpl) Error!void {
        if (!self.process.kernel_mode) {
            platform.segments.set_interrupt_handler_stack(self.kernelmode_stack.end() - 1);
        }
        var current_page_directory: ?[]u32 = null;
        if (kernel.kernel.threading_manager.current_process) |current| {
            current_page_directory = current.impl.page_directory;
        }
        try pmemory.load_page_directory(self.page_directory, current_page_directory);
        // TODO: Try to undo the effects if there is an error.
        if (!self.main_thread_is_setup) {
            const stack_range =
                if (self.process.kernel_mode) self.kernelmode_stack else self.usermode_stack;
            const stack_address = stack_range.end() - 1;
            self.process.main_thread.impl.setup_context(stack_address, self.process.entry);
            self.main_thread_is_setup = true;
        }
    }

    pub fn start(self: *ProcessImpl) Error!void {
        self.process.main_thread.impl.switch_to();
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
