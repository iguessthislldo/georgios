const std = @import("std");

const kernel = @import("../kernel.zig");
const kthreading = @import("../threading.zig");
const Thread = kthreading.Thread;
const Process = kthreading.Process;
const kutil = @import("../util.zig");
const kmemory = @import("../memory.zig");
const Range = kmemory.Range;
const print = @import("../print.zig");

const platform = @import("platform.zig");
const pmemory = @import("memory.zig");
const interrupts = @import("interrupts.zig");
const InterruptStack = interrupts.InterruptStack;

pub const Error = kutil.Error || kmemory.MemoryError;

const pmem = &kernel.memory.platform_memory;

pub extern fn setup_process(usermode: bool, ip: u32, sp: u32) u32;
pub extern fn context_switch(old: u32, new: u32) void;
pub extern fn usermode(ip: u32, sp: u32) noreturn;

pub const ThreadImpl = struct {
    thread: *Thread,
    context: usize,
    context_is_setup: bool,
    usermode_stack: Range,
    kernelmode_stack: Range,

    pub fn init(self: *ThreadImpl, thread: *Thread, boot_thread: bool) Error!void {
        self.thread = thread;
        self.context_is_setup = boot_thread;
        if (!boot_thread) {
            self.kernelmode_stack = try kernel.memory.big_alloc.alloc_range(kutil.Ki(4));
        }
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

    /// Initial Kernel Mode Stack/Context in switch_to() for New Threads
    const SwitchToFrame = packed struct {
        // pusha
        edi: u32,
        esi: u32,
        ebp: u32,
        esp: u32,
        ebx: u32,
        edx: u32,
        ecx: u32,
        eax: u32,
        // pushf
        eflags: u32,
        // switch_to() Base Frame
        func_eax: u32,
        func_ebx: u32,
        func_ebp: u32,
        func_return: u32,
        // run() Frame
        run_return: u32,
        run_arg: u32,
    };

    /// Setup Initial Kernel Mode Stack/Context in switch_to() for New Threads
    fn setup_context(self: *ThreadImpl) void {
        // Setup Usermode Stack
        if (!self.thread.kernel_mode) {
            if (self.thread.process) |process| {
                self.usermode_stack = Range{
                    .start = platform.kernel_to_virtual(0) - platform.frame_size,
                    .size = platform.frame_size};
                pmem.mark_virtual_memory_present(
                    process.impl.page_directory, self.usermode_stack, true)
                    catch @panic("setup_context: mark_virtual_memory_present");
            }
        }

        // Setup Initial Kernel Mode Stack/Context
        const sp = self.kernelmode_stack.end() - 1;
        self.context = sp;
        var frame = kutil.zero_init(SwitchToFrame);
        frame.esp = sp;
        // TODO: Zig Bug? @ptrToInt(&run) results in weird address
        frame.func_return = @ptrToInt(run);
        frame.func_ebp = sp;
        frame.run_arg = @ptrToInt(self);
        self.push_to_context(frame);
    }

    pub fn before_switch(self: *ThreadImpl) void {
        if (!self.context_is_setup) {
            self.setup_context();
            self.context_is_setup = true;
        }
        if (self.thread.process) |process| {
            process.impl.switch_to() catch @panic("before_switch: ProcessImpl.switch_to");
        }
        if (!self.thread.kernel_mode) {
            platform.segments.set_interrupt_handler_stack(self.kernelmode_stack.end() - 1);
        }
        kernel.threading_manager.current_process = self.thread.process;
        kernel.threading_manager.current_thread = self.thread;
    }

    pub fn switch_to(self: *ThreadImpl) callconv(.C) void {
        // WARNING: A FRAME FOR THIS FUNCTION NEEDS TO BE SETUP IN setup_context!
        const last = kernel.threading_manager.current_thread.?;
        self.before_switch();
        asm volatile (
            \\pushf
            \\pusha
            \\movl %%esp, (%[old_context_ptr])
            \\movl %[new_context], %%esp
            \\popa
            \\popf
            : :
                [old_context_ptr] "{ax}" (@ptrToInt(&last.impl.context)),
                [new_context] "{bx}" (self.context));
        after_switch();
    }

    pub fn after_switch() void {
        if (interrupts.in_tick) {
            print.char('#');
            interrupts.pic.end_of_interrupt(0, false);
            interrupts.in_tick = false;
            platform.enable_interrupts();
        }
    }

    pub fn run_impl(self: *ThreadImpl) void {
        self.before_switch();
        if (self.thread.kernel_mode) {
            platform.enable_interrupts();
            asm volatile ("call *%[entry]" : : [entry] "{ax}" (self.thread.entry));
        } else {
            usermode(self.thread.entry, self.usermode_stack.end() - 1);
        }
    }

    // WARNING: THIS FUNCTION'S ARGUMENTS NEED TO BE SETUP IN setup_context!
    pub fn run(self: *ThreadImpl) callconv(.C) void {
        print.format("Thread {} has Started\n", .{self.thread.id});
        self.run_impl();
    }
};

pub const ProcessImpl = struct {
    process: *Process,
    page_directory: []u32,

    pub fn init(self: *ProcessImpl, process: *Process) Error!void {
        self.process = process;
        self.page_directory = try pmem.new_page_directory();
    }

    // TODO: Cleanup

    pub fn switch_to(self: *ProcessImpl) Error!void {
        var current_page_directory: ?[]u32 = null;
        if (kernel.threading_manager.current_process) |current| {
            current_page_directory = current.impl.page_directory;
        }
        try pmemory.load_page_directory(self.page_directory, current_page_directory);
        // TODO: Try to undo the effects if there is an error.
    }

    pub fn start(self: *ProcessImpl) Error!void {
        self.process.main_thread.impl.switch_to();
    }

    pub fn address_space_copy(self: *ProcessImpl,
            address: usize, data: []const u8) kmemory.AllocError!void {
        try pmem.page_directory_memory_copy(
            self.page_directory, address, data);
    }

    pub fn address_space_set(self: *ProcessImpl,
            address: usize, byte: u8, len: usize) kmemory.AllocError!void {
        try pmem.page_directory_memory_set(
            self.page_directory, address, byte, len);
    }
};
