const builtin = @import("builtin");
const build_options = @import("build_options");
const std = @import("std");

pub const platform = @import("platform.zig");
pub const print = @import("print.zig");
pub const Memory = @import("memory.zig").Memory;
pub const io = @import("io.zig");
pub const elf = @import("elf.zig");
pub const util = @import("util.zig");
pub const Ext2 = @import("ext2.zig").Ext2;
pub const Devices = @import("devices.zig").Devices;

pub var panic_message: []const u8 = "";
extern var __debug_info_start: u8;
extern var __debug_info_end: u8;
extern var __debug_abbrev_start: u8;
extern var __debug_abbrev_end: u8;
extern var __debug_str_start: u8;
extern var __debug_str_end: u8;
extern var __debug_line_start: u8;
extern var __debug_line_end: u8;
extern var __debug_ranges_start: u8;
extern var __debug_ranges_end: u8;
var kernel_panic_allocator_bytes: [100 * 1024]u8 = undefined;
var kernel_panic_allocator_state = std.heap.FixedBufferAllocator.init(kernel_panic_allocator_bytes[0..]);
const kernel_panic_allocator = &kernel_panic_allocator_state.allocator;

fn dwarfSectionFromSymbolAbs(start: *u8, end: *u8) std.debug.DwarfInfo.Section {
    return std.debug.DwarfInfo.Section{
        .offset = 0,
        .size = @ptrToInt(end) - @ptrToInt(start),
    };
}

fn dwarfSectionFromSymbol(start: *u8, end: *u8) std.debug.DwarfInfo.Section {
    return std.debug.DwarfInfo.Section{
        .offset = @ptrToInt(start),
        .size = @ptrToInt(end) - @ptrToInt(start),
    };
}

fn getSelfDebugInfo() !*std.debug.DwarfInfo {
    const S = struct {
        var have_self_debug_info = false;
        var self_debug_info: std.debug.DwarfInfo = undefined;

        var in_stream_state = std.io.InStream(anyerror){ .readFn = readFn };
        var in_stream_pos: u64 = 0;
        const in_stream = &in_stream_state;

        fn readFn(self: *std.io.InStream(anyerror), buffer: []u8) anyerror!usize {
            const ptr = @intToPtr([*]const u8, @intCast(usize, in_stream_pos));
            @memcpy(buffer.ptr, ptr, buffer.len);
            in_stream_pos += buffer.len;
            return buffer.len;
        }

        const SeekableStream = std.io.SeekableStream(anyerror, anyerror);
        var seekable_stream_state = SeekableStream{
            .seekToFn = seekToFn,
            .seekByFn = seekByFn,

            .getPosFn = getPosFn,
            .getEndPosFn = getEndPosFn,
        };
        const seekable_stream = &seekable_stream_state;

        fn seekToFn(self: *SeekableStream, pos: u64) anyerror!void {
            in_stream_pos = pos;
        }
        fn seekByFn(self: *SeekableStream, pos: i64) anyerror!void {
            in_stream_pos = @bitCast(u64, @bitCast(i64, in_stream_pos) +% pos);
        }
        fn getPosFn(self: *SeekableStream) anyerror!u64 {
            return in_stream_pos;
        }
        fn getEndPosFn(self: *SeekableStream) anyerror!u64 {
            return @ptrToInt(&__debug_ranges_end);
        }
    };
    if (S.have_self_debug_info) return &S.self_debug_info;

    S.self_debug_info = std.debug.DwarfInfo{
        .dwarf_seekable_stream = S.seekable_stream,
        .dwarf_in_stream = S.in_stream,
        .endian = builtin.Endian.Little,
        .debug_info = dwarfSectionFromSymbol(&__debug_info_start, &__debug_info_end),
        .debug_abbrev = dwarfSectionFromSymbolAbs(&__debug_abbrev_start, &__debug_abbrev_end),
        .debug_str = dwarfSectionFromSymbolAbs(&__debug_str_start, &__debug_str_end),
        .debug_line = dwarfSectionFromSymbol(&__debug_line_start, &__debug_line_end),
        .debug_ranges = dwarfSectionFromSymbolAbs(&__debug_ranges_start, &__debug_ranges_end),
        .abbrev_table_list = undefined,
        .compile_unit_list = undefined,
        .func_list = undefined,
    };
    try std.debug.openDwarfDebugInfo(&S.self_debug_info, kernel_panic_allocator);
    return &S.self_debug_info;
}

fn printLineFromFile(out_stream: var, line_info: std.debug.LineInfo) anyerror!void {
    print.string("TODO print line from the file\n");
}

pub fn panic(msg: []const u8, trace: ?*builtin.StackTrace) noreturn {
    panic_message = msg;
    const dwarf_info = getSelfDebugInfo() catch |e| {
        print.format("Failed to get debug info: {}\n", @errorName(e));
        platform.panic(msg, trace);
    };
    if (print.console_file) |file| {
        const out = file.get_std_out_stream();
        var i = std.debug.StackIterator.init(@returnAddress());
        while (i.next()) |address| {
            std.debug.printSourceAtAddressDwarf(
                    dwarf_info, out, address, false, printLineFromFile) catch |e| {
                print.format("Failed to get line info for {:a}: {}\n",
                    address, @errorName(e));
                continue;
            };
        }
    }
    platform.panic(msg, trace);
}

extern fn usermode(ip: u32, sp: u32) noreturn;

pub const Kernel = struct {
    console: io.File = io.File{},
    memory: Memory = Memory{},
    devices: Devices = Devices{},
    raw_block_store: ?*io.BlockStore = null,
    block_store: io.CachedBlockStore = io.CachedBlockStore{},
    filesystem: Ext2 = Ext2{},

    pub fn initialize(self: *Kernel) !void {
        print.initialize(&self.console, build_options.debug_log);
        try platform.initialize(self);
        if (self.raw_block_store) |raw| {
            self.block_store.init(self.memory.small_alloc, raw, 128);
            try self.filesystem.initialize(self.memory.small_alloc, &self.block_store.block_store);
        } else {
            print.format("No block store set\n");
        }
    }

    pub fn run(self: *Kernel) !void {
        try self.initialize();

        var ext2_file = try self.filesystem.open("echoer.elf");
        const file = &ext2_file.io_file;
        var elf_object = try elf.Object.from_file(self.memory.small_alloc, file);
        const Range = @import("memory.zig").Range;
        const range = Range{.start=0, .size=elf_object.program.len};
        try self.memory.platform_memory.mark_virtual_memory_present(range, true);
        var i: usize = 0;
        while (i < range.size) {
            @intToPtr(*allowzero u32, range.start + i).* = elf_object.program[i];
            i += 1;
        }
        const usermode_stack = Range{
            .start = platform.impl.kernel_to_virtual(0) - platform.frame_size,
            .size = platform.frame_size};
        try self.memory.platform_memory.mark_virtual_memory_present(usermode_stack, true);
        const kernelmode_stack = try self.memory.big_alloc.alloc_range(util.Ki(4));
        platform.impl.segments.set_usermode_interrupt_stack(kernelmode_stack.end() - 1);
        usermode(elf_object.header.entry, usermode_stack.end());
    }
};

var kernel = Kernel{};

pub export fn kernel_main() void {
    if (kernel.run()) |_| {} else |e| {
        panic(@errorName(e), @errorReturnTrace());
    }
    print.string("Done\n");
    platform.done();
}
