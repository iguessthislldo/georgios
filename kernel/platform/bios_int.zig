// Invoke BIOS interrupts using an emulated CPU so we don't have to mess with
// how our CPU is setup by going to real mode ourselves or using v8086 mode
// and a monitor.
//
// Uses libx86emu https://github.com/wfeldt/libx86emu
// This lives in a submodule in bios_int/libx86emu/, with C support code in
// bios_int/.

const utils = @import("utils");

const print = @import("../print.zig");
const kernel = @import("../kernel.zig");
const memory = @import("../memory.zig");

const platform = @import("platform.zig");
const util = @import("util.zig");
const timing = @import("timing.zig");

const c = @cImport({
    @cInclude("georgios_bios_int.h");
});

pub const Error = error {
    BiosIntCallFailed,
};

pub const Params = struct {
    interrupt: u8,
    eax: u32,
    ebx: u32 = 0,
    ecx: u32 = 0,
    edx: u32 = 0,
    edi: u32 = 0,
    slow: bool = false,
};

const debug_io_access = false;
const debug_mem_access = false;
const exec_trace = false;

export fn georgios_bios_int_to_string(
        buffer: [*]u8, buffer_size: usize, got: *usize, kind: u8, value: *c_void) bool {
    var ts = utils.ToString{.buffer = buffer[0..buffer_size]};
    switch (kind) {
        's' => {
            ts.cstring(@ptrCast([*:0]const u8, value)) catch return true;
        },
        'x' => {
            var v: usize = undefined;
            utils.memory_copy_anyptr(utils.to_bytes(&v), value);
            ts.hex(v) catch return true;
        },
        else => {
            print.format("georgios_bios_to_string: Unexpected kind {:c}\n", .{kind});
        },
    }
    got.* = ts.got;
    return false;
}

export fn georgios_bios_int_print_string(str: [*:0]const u8) void {
    var i: usize = 0;
    while (str[i] != 0) {
        print.char(str[i]);
        i += 1;
    }
}

export fn georgios_bios_int_print_value(value: u32) void {
    print.hex(value);
}


export fn georgios_bios_int_wait() void {
    timing.wait_microseconds(500);
}

export fn georgios_bios_int_malloc(size: usize) ?*c_void {
    const a = kernel.memory.small_alloc.alloc_array(u8, size) catch return null;
    return @ptrCast(*c_void, a.ptr);
}

export fn georgios_bios_int_calloc(num: usize, size: usize) ?*c_void {
    const a = kernel.memory.small_alloc.alloc_array(u8, size * num) catch return null;
    utils.memory_set(a, 0);
    return @ptrCast(*c_void, a.ptr);
}

export fn georgios_bios_int_free(ptr: ?*c_void) void {
    if (ptr != null) {
        kernel.memory.small_alloc.free_array(
            utils.make_const_slice(u8, @ptrCast([*]u8, ptr), 0)) catch {};
    }
}

export fn georgios_bios_int_strcat(dest: [*c]u8, src: [*c]const u8) [*c]u8 {
    var dest_i: usize = 0;
    while (dest[dest_i] != 0) {
        dest_i += 1;
    }
    var src_i: usize = 0;
    while (src[src_i] != 0) {
        dest[dest_i] = src[src_i];
        dest_i += 1;
        src_i += 1;
    }
    dest[dest_i] = 0;
    return dest;
}

// For Access to I/O Ports
export fn georgios_bios_int_inb(port: u16) callconv(.C) u8 {
    if (debug_io_access) print.format("georgios_bios_int_inb {:x}\n", .{port});
    return util.in8(port);
}
export fn georgios_bios_int_inw(port: u16) callconv(.C) u16 {
    if (debug_io_access) print.format("georgios_bios_int_inw {:x}\n", .{port});
    return util.in16(port);
}
export fn georgios_bios_int_inl(port: u16) callconv(.C) u32 {
    if (debug_io_access) print.format("georgios_bios_int_inl {:x}\n", .{port});
    return util.in32(port);
}
export fn georgios_bios_int_outb(port: u16, value: u8) callconv(.C) void {
    if (debug_io_access) print.format("georgios_bios_int_outb {:x}, {:x}\n", .{port, value});
    return util.out8(port, value);
}
export fn georgios_bios_int_outw(port: u16, value: u16) callconv(.C) void {
    if (debug_io_access) print.format("georgios_bios_int_outw {:x}, {:x}\n", .{port, value});
    return util.out16(port, value);
}
export fn georgios_bios_int_outl(port: u16, value: u32) callconv(.C) void {
    if (debug_io_access) print.format("georgios_bios_int_outl {:x}, {:x}\n", .{port, value});
    return util.out32(port, value);
}

export fn georgios_bios_int_fush_log_impl(buf: [*c]u8, size: c_uint) void {
    print.string(buf[0..size]);
}

// For Access to Memory
export fn georgios_bios_int_rdb(addr: u32) callconv(.C) u8 {
    @setRuntimeSafety(false);
    const value = @intToPtr(*allowzero u8, addr).*;
    if (debug_mem_access) print.format("georgios_bios_int_rdb {:x} ({:x})\n", .{addr, value});
    return value;
}
export fn georgios_bios_int_rdw(addr: u32) callconv(.C) u16 {
    @setRuntimeSafety(false);
    const value = @intToPtr(*allowzero u16, addr).*;
    if (debug_mem_access) print.format("georgios_bios_int_rdw {:x} ({:x})\n", .{addr, value});
    return value;
}
export fn georgios_bios_int_rdl(addr: u32) callconv(.C) u32 {
    @setRuntimeSafety(false);
    const value = @intToPtr(*allowzero u32, addr).*;
    if (debug_mem_access) print.format("georgios_bios_int_rdl {:x} ({:x})\n", .{addr, value});
    return value;
}
export fn georgios_bios_int_wrb(addr: u32, value: u8) callconv(.C) void {
    if (debug_mem_access) print.format("georgios_bios_int_wrb {:x}, {:x}\n", .{addr, value});
    @setRuntimeSafety(false);
    @intToPtr(*allowzero u8, addr).* = value;
}
export fn georgios_bios_int_wrw(addr: u32, value: u16) callconv(.C) void {
    if (debug_mem_access) print.format("georgios_bios_int_wrw {:x}, {:x}\n", .{addr, value});
    @setRuntimeSafety(false);
    @intToPtr(*allowzero u16, addr).* = value;
}
export fn georgios_bios_int_wrl(addr: u32, value: u32) callconv(.C) void {
    if (debug_mem_access) print.format("georgios_bios_int_wrl {:x}, {:x}\n", .{addr, value});
    @setRuntimeSafety(false);
    @intToPtr(*allowzero u32, addr).* = value;
}

pub fn init() void {
    c.georgios_bios_int_init(exec_trace);
}

pub fn run(params: *Params) Error!void {
    const pmem = &kernel.memory.platform_memory;
    pmem.map(.{.start = 0, .size = utils.Mi(1)}, 0, false)
        catch @panic("bios_int map");

    var c_params = c.GeorgiosBiosInt{
        .interrupt = params.interrupt,
        .eax = params.eax,
        .ebx = params.ebx,
        .ecx = params.ecx,
        .edx = params.edx,
        .edi = params.edi,
        .slow = params.slow,
    };
    const failed = c.georgios_bios_int_run(&c_params);
    params.eax = c_params.eax;
    params.ebx = c_params.ebx;
    params.ecx = c_params.ecx;
    params.edx = c_params.edx;
    params.edi = c_params.edi;
    params.slow = false;

    if (failed) {
        return Error.BiosIntCallFailed;
    }
}

pub fn done() void {
    c.georgios_bios_int_done();
}
