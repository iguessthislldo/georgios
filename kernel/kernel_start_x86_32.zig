// Multiboot stuff for bootloader to find, entry point, and setup for
// kernel_main().
//
// This replaced an assembly file I used since the beginning and is based on
// Andrew Kelly's neat example:
// https://github.com/andrewrk/HellOS/blob/master/hellos.zig
//
// It is here instead of in the x86_32 specific location because I think it
// needs to be the root zig file and I don't think the root zig file can be in
// a subdirectory of a zig package. I'm fine with such an important file being
// an exception for platforms.

const std = @import("std");
const builtin = @import("builtin");
const build_options = @import("build_options");

const kernel = @import("kernel.zig");
const kernel_main = kernel.kernel_main;
const utils = @import("utils");

const sse_enabled: bool = comptime {
    for (builtin.arch.allFeaturesList()) |feature, index_usize| {
        const index = @intCast(std.Target.Cpu.Feature.Set.Index, index_usize);
        if (builtin.cpu.features.isEnabled(index)) {
            if (feature.name.len >= 3 and std.mem.eql(u8, feature.name[0..3], "sse")) {
                return true;
            }
        }
    }
    return false;
};

pub fn panic(msg: []const u8, trace: ?*builtin.StackTrace) noreturn {
    kernel.panic(msg, trace);
}

// TODO: Maybe refactor when struct fields get custom alignment
const Multiboot2Header = packed struct {
    const magic_value: u32 = 0xe85250d6;

    const architecture_x86_32: u32 = 0;
    const architecture_value: u32 = architecture_x86_32;

    const tag_kind_end = 0;
    const tag_kind_info_request = 1;
    const tag_kind_framebuffer = 5;

    const tag_flag_must_understand: u16 = 0;
    const tag_flag_optional: u16 = 1;

    const VgaMode = if (build_options.multiboot_vbe) packed struct {
        const InfoRequestTag = packed struct {
            kind: u16 = tag_kind_info_request,
            flags: u16 = tag_flag_must_understand,
            size: u32 = @sizeOf(@This()),
            tag0: u32 = 7, // VBE
        };

        const FramebufferTag = packed struct {
            kind: u16 = tag_kind_framebuffer,
            flags: u16 = tag_flag_must_understand,
            size: u32 = @sizeOf(@This()),
            width: u32 = 1024,
            height: u32 = 768,
            depth: u32 = 32,
        };

        info_request_tag: InfoRequestTag = InfoRequestTag{},
        padding0: u32 = 0,
        framebuffer_tag: FramebufferTag = FramebufferTag{},
        padding1: u32 = 0,
    } else void;

    magic: u32 = magic_value,
    architecture: u32 = architecture_value,
    header_length: u32 = @sizeOf(@This()),
    checksum: u32 = @bitCast(u32, -(@bitCast(i32,
        magic_value + architecture_value + @sizeOf(@This())))),

    vga_mode: VgaMode = VgaMode{},

    end_tag_kind: u16 = tag_kind_end,
    end_tag_flags: u16 = tag_flag_must_understand,
    end_tag_size: u32 = 8,
};
export var multiboot2_header align(8) linksection(".multiboot") =
    Multiboot2Header{};

/// Real Address of multiboot_info
extern var low_multiboot_info: []u32;

/// Real Address of kernel_range_start_available
extern var low_kernel_range_start_available: u32;

/// Real Address of kernel_page_table_count
extern var low_kernel_page_table_count: u32;

/// Real Address of kernel_page_tables
extern var low_kernel_page_tables: []u32;

/// Real Address of page_directory
extern var low_page_directory: [utils.Ki(1)]u32;

/// Stack for kernel_main_wrapper(). This will be reclaimed later as a frame
/// when the memory system is initialized.
pub export var temp_stack: [utils.Ki(4)]u8
    align(utils.Ki(4)) linksection(".low_bss") = undefined;

/// Stack for kernel_main()
export var stack: [utils.Ki(8)]u8 align(16) linksection(".bss") = undefined;

/// Entry Point
export fn kernel_start() linksection(".low_text") callconv(.Naked) noreturn {
    @setRuntimeSafety(false);

    // Save location of Multiboot2 Info
    low_multiboot_info.ptr = asm volatile (
        // Check for the Multiboot2 magic value in eax. It is a fatal error if
        // we don't have it, but we can't report it yet so set the pointer to 0
        // and we will panic later when we first try to use it.
        //
        \\ cmpl $0x36d76289, %%eax
        \\ je passed_multiboot_check
        \\ mov $0, %%ebx
        \\ passed_multiboot_check:
    :
        [rv] "={ebx}" (-> [*]u32)
    );

    // This just forces Zig to include multiboot2_header, which export isn't
    // doing for some reason. TODO: Report as bug?
    if (multiboot2_header.magic != 0xe85250d6) {
        asm volatile ("nop");
    }

    // Not using @newStackCall as it seems to assume there is an existing
    // stack.
    asm volatile (
        \\ mov %[temp_stack_end], %%esp
        \\ jmp kernel_main_wrapper
    ::
        [temp_stack_end] "{eax}" (
            @ptrToInt(&temp_stack[0]) + temp_stack.len)
    );
    unreachable;
}

extern var _VIRTUAL_OFFSET: u32;
extern var _REAL_START: u32;
extern var _REAL_END: u32;
extern var _FRAME_SIZE: u32;

fn align_down(value: u32, align_by: u32) linksection(".low_text") u32 {
    return value & -%(align_by);
}

fn align_up(value: u32, align_by: u32) linksection(".low_text") u32 {
    return align_down(value + align_by - 1, align_by);
}

/// Get setup for kernel_main
export fn kernel_main_wrapper() linksection(".low_text") noreturn {
    @setRuntimeSafety(false);
    // Otherwise Zig inserts a call to a high kernel linked internal function
    // called __zig_probe_stack at the start. Runtime safety doesn't do much
    // good before kernel_main anyway.
    // TODO: Report as bug?

    const offset = @ptrToInt(&_VIRTUAL_OFFSET);
    const kernel_end = @ptrToInt(&_REAL_END);
    const frame_size = @ptrToInt(&_FRAME_SIZE);
    const after_kernel = align_up(kernel_end, frame_size);
    const pages_per_table = 1 << 10;

    // If we have it, copy Multiboot information because we could accidentally
    // overwrite it. Otherwise continue to defer the error.
    var page_tables_start: u32 = after_kernel;
    if (@ptrToInt(low_multiboot_info.ptr) != 0) {
        const multiboot_info_size = low_multiboot_info[0];
        low_multiboot_info.len = multiboot_info_size >> 2;
        var multiboot_info_dest = after_kernel;
        for (low_multiboot_info) |*ptr, i| {
            @intToPtr([*]u32, multiboot_info_dest)[i] = ptr.*;
        }
        low_multiboot_info.ptr = @intToPtr([*]u32, multiboot_info_dest + offset);
        const multiboot_info_end = multiboot_info_dest + multiboot_info_size;
        page_tables_start = align_up(multiboot_info_end, frame_size);
    }

    // Create Page Tables for First 1MiB + Kernel + Multiboot + Page Tables
    // This is an iterative process for now. Start with 1 table, see if that's
    // enough. If not add another table.
    var frame_count: usize = (page_tables_start / frame_size) + 1;
    while (true) {
        low_kernel_page_table_count =
            align_up(frame_count, pages_per_table) / pages_per_table;
        if (frame_count <= low_kernel_page_table_count * pages_per_table) {
            break;
        }
        frame_count += 1;
    }
    const low_page_tables_end = page_tables_start +
        low_kernel_page_table_count * frame_size;

    // Set the start of what the memory system can work with.
    low_kernel_range_start_available = low_page_tables_end;

    // Get Slice for the Initial Page Tables
    low_kernel_page_tables.ptr =
        @intToPtr([*]u32, @intCast(usize, page_tables_start));
    low_kernel_page_tables.len = pages_per_table * low_kernel_page_table_count;

    // Initialize Paging Structures to Zeros
    for (low_page_directory[0..]) |*ptr| {
        ptr.* = 0;
    }
    for (low_kernel_page_tables[0..]) |*ptr| {
        ptr.* = 0;
    }

    // Virtually Map Kernel to the Real Location and the Kernel Offset
    var table_i: usize = 0;
    while (table_i < low_kernel_page_table_count) {
        const table_start = &low_kernel_page_tables[table_i * utils.Ki(1)];
        const entry = (@ptrToInt(table_start) & 0xFFFFF000) | 1;
        low_page_directory[table_i] = entry;
        low_page_directory[(offset >> 22) + table_i] = entry; // Div by 4MiB
        table_i += 1;
    }
    for (low_kernel_page_tables[0..frame_count]) |*ptr, i| {
        ptr.* = i * utils.Ki(4) + 1;
    }
    low_kernel_page_tables[0] = 0;
    // Translate for high mode
    low_kernel_page_tables.ptr =
        @intToPtr([*]u32, @ptrToInt(low_kernel_page_tables.ptr) + offset);

    // Use that Paging Scheme
    asm volatile (
        \\ // Set Page Directory
        \\ mov $low_page_directory, %%eax
        \\ mov %%eax, %%cr3

        \\ // Enable Paging
        \\ mov %%cr0, %%eax
        \\ or $0x80000001, %%eax
        \\ mov %%eax, %%cr0
    :::
        "eax"
    );

    // Zig 0.6 will try to use SSE in normal generated code, at least while
    // setting an array to undefined in debug mode. Enable SSE to allow that to
    // work.
    // This also allows us to explicitly take advantage of it.
    // Based on the initialization code in https://wiki.osdev.org/SSE
    // TODO: Disabled for now in build.zig because we need to support saving
    // and restoring SSE registers first.
    if (sse_enabled) {
        asm volatile (
            \\ mov %%cr0, %%eax
            \\ and $0xFFFB, %%ax
            \\ or $0x0002, %%ax
            \\ mov %%eax, %%cr0

            \\ mov %%cr4, %%eax
            \\ or $0x0600, %%ax
            \\ mov %%eax, %%cr4
        :::
            "eax"
        );
    }

    // Start the generic main function, jumping to high memory kernel at the
    // same time.
    asm volatile (
        \\mov %[stack_end], %%esp
    ::
        [stack_end] "{eax}" (
            @ptrToInt(&stack[0]) + stack.len)
    );
    kernel_main();
    unreachable;
}
