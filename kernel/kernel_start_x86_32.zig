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

const kernel = @import("kernel.zig");
const kernel_main = kernel.kernel_main;
const util = @import("util.zig");

pub const panic = kernel.panic;

// TODO: Be able to toggle without changing source
// TODO: Be able to use VGA
const request_vga_mode = false;

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

    const VgaMode = if (request_vga_mode) packed struct {
        const InfoRequestTag = packed struct {
            kind: u16 = tag_kind_info_request,
            flags: u16 = tag_flag_must_understand,
            size: u32 = @sizeOf(@This()) - 8,
            tag0: u32 = 7, // VBE
            padding: u32 = 0,
        };
        info_request_tag: InfoRequestTag = InfoRequestTag{},

        const FramebufferTag = packed struct {
            kind: u16 = tag_kind_framebuffer,
            flags: u16 = tag_flag_must_understand,
            size: u32 = @sizeOf(@This()),
            width: u32 = 1024,
            height: u32 = 768,
            depth: u32 = 32,
        };
        framebuffer_tag: FramebufferTag = FramebufferTag{},
    } else packed struct{};

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

/// Real Address of multiboot_info_pointer
extern var low_multiboot_info_pointer: u32;

/// Stack for kernel_main_wrapper(). This will be reclaimed later as a frame
/// when the memory system is initialized.
export var temp_stack: [util.Ki(4)]u8 align(util.Ki(4)) linksection(".low_bss") = undefined;

/// Stack for kernel_main()
/// TODO: Allow this to grow later or what ever kernel stacks are supposed to
/// do?
export var stack: [util.Ki(16)]u8 align(16) linksection(".bss") = undefined;

export var page_directory: [util.Ki(1)]u32 align(util.Ki(4)) linksection(".data") = undefined;
extern var low_page_directory: [util.Ki(1)]u32;
export var kernel_page_table: [util.Ki(1)]u32 align(util.Ki(4)) linksection(".bss") = undefined;
extern var low_kernel_page_table: [util.Ki(1)]u32;

/// Entry Point
export nakedcc fn kernel_start() linksection(".low_text") noreturn {
    @setRuntimeSafety(false);

    // Save location of Multiboot2 Info
    low_multiboot_info_pointer = asm volatile (
        // Check for the Multiboot2 magic value in eax. If we don't have it,
        // then is a fatal error, but we can't report it yet so set the pointer
        // to 0 and we will panic later when we first try to use it.
        //
        \\ cmpl $0x36d76289, %%eax
        \\ je passed_multiboot_check
        \\ mov $0, %%ebx
        \\ passed_multiboot_check:
    :
        [rv] "={ebx}" (-> u32)
    );

    // Not using @newStackCall as that seems to not work when
    asm volatile (
        \\ mov %[temp_stack_end], %%esp
        \\ jmp kernel_main_wrapper
    ::
        [temp_stack_end] "{eax}" (
            @ptrToInt(&temp_stack[0]) + temp_stack.len)
    );

    // This should never be ran, forces Zig to include multiboot2_header, which
    // export isn't doing for some reason.
    // TODO: Report as bug?
    if (multiboot2_header.magic != 0xe85250d6) {
        unreachable;
    }

    unreachable;
}

extern var _KERNEL_OFFSET: u32;

/// Make it possible to run kernel_main in high virtual memory, then run it.
export fn kernel_main_wrapper() linksection(".low_text") noreturn {
    @setRuntimeSafety(false);
    // Otherwise Zig inserts a call to a high kernel linked internal function
    // called __zig_probe_stack at the start. Runtime safety doesn't do much
    // good before kernel_main anyway.
    // TODO: Report as bug?

    // Initialize Paging Structures to Zeros
    for (low_page_directory[0..]) |*ptr| {
        ptr.* = 0;
    }
    for (low_kernel_page_table[0..]) |*ptr| {
        ptr.* = 0;
    }

    // Virtually Map Kernel to the Real Location and the Kernel Offset
    // TODO: Do so dynamically based on the size of the kernel
    const offset = @ptrToInt(&_KERNEL_OFFSET);
    const kernel_entry =
        (@ptrToInt(&low_kernel_page_table[0]) & 0xFFFFF000) | 1;
    low_page_directory[0] = kernel_entry;
    low_page_directory[offset >> 22] = kernel_entry; // Div by 4MiB
    for (low_kernel_page_table[0..]) |*ptr, i| {
        ptr.* = i * util.Ki(4) + 1;
    }

    // Use that Paging Scheme
    asm volatile (
        \\ // Set Page Directory
        \\ mov $low_page_directory, %%eax
        \\ mov %%eax, %%cr3

        \\ // Enable Paging
        \\ mov %%cr0, %%eax
        \\ or $0x80000001, %%eax
        \\ mov %%eax, %%cr0

        \\ // Jump to Higher Kernel
        \\ movl $higher_kernel, %%eax
        \\ jmp * %%eax
        \\ higher_kernel:
    :::
        "eax"
    );

    // Start the main platform agnostic function
    @newStackCall(stack[0..], kernel_main);
    unreachable;
}
