// VESA BIOS Extensions (VBE) Version 2
//
// https://en.wikipedia.org/wiki/VESA_BIOS_Extensions
// https://wiki.osdev.org/VESA_Video_Modes

const std = @import("std");
const build_options = @import("build_options");

const utils = @import("utils");

const multiboot = @import("multiboot.zig");
const pmemory = @import("memory.zig");
const putil = @import("util.zig");
const bios_int = @import("bios_int.zig");
const vbe_console = @import("vbe_console.zig");

const kernel = @import("root").kernel;
const print = kernel.print;
const kmemory = kernel.memory;
const Range = kmemory.Range;
pub const font = kernel.font;

// TODO Make these not fixed
const find_width = 800;
const find_height = 600;
const find_bpp = 24;

const RealModePtr = packed struct {
    offset: u16,
    segment: u16,

    pub fn get(self: *const RealModePtr) u32 {
        return @intCast(u32, self.segment) * 0x10 + self.offset;
    }
};

const Info = packed struct {
    const magic_expected = "VESA";

    magic: [4]u8,
    version: u16,
    oem_ptr: RealModePtr,
    capabilities: u32,
    video_modes_ptr: RealModePtr,
    memory: u16,
    software_rev: u16,
    vendor: RealModePtr,
    product_name: RealModePtr,
    product_rev: RealModePtr,

    const Version = enum (u8) {
        V1 = 1,
        V2 = 2,
        V3 = 3,
    };

    pub fn get_version(self: *const Info) ?Version {
        return utils.int_to_enum(Version, @intCast(u8, self.version >> 8));
    }

    pub fn get_modes(self: *const Info) []const u16 {
        var mode_count: usize = 0;
        const modes_ptr = @intToPtr([*]const u16, self.video_modes_ptr.get());
        while (modes_ptr[mode_count] != 0xffff) {
            mode_count += 1;
        }
        const modes = kernel.alloc.alloc_array(u16, mode_count) catch
            @panic("vbe.Info.get_modes: alloc mode array failed");
        var mode_i: usize = 0;
        while (modes_ptr[mode_i] != 0xffff) {
            modes[mode_i] = modes_ptr[mode_i];
            mode_i += 1;
        }
        return modes;
    }
};

const Mode = packed struct {
    attributes: u16,
    window_a: u8,
    window_b: u8,
    granularity: u16,
    window_size: u16,
    segment_a: u16,
    segment_b: u16,
    win_func_ptr: u32,
    pitch: u16,
    width: u16,
    height: u16,
    w_char: u8,
    y_char: u8,
    planes: u8,
    bpp: u8,
    banks: u8,
    memory_model: u8,
    bank_size: u8,
    image_pages: u8,
    reserved0: u8,
    red_mask: u8,
    red_position: u8,
    green_mask: u8,
    green_position: u8,
    blue_mask: u8,
    blue_position: u8,
    reserved_mask: u8,
    reserved_position: u8,
    direct_color_attributes: u8,
    framebuffer: u32,
    off_screen_mem_off: u32,
    off_screen_mem_size: u16,
};

var vbe_setup = false;
var info: Info = undefined;
var mode: Mode = undefined;
var mode_id: ?u16 = null;

fn video_memory_offset(x: u32, y: u32) callconv(.Inline) u32 {
    return y * mode.pitch + x * bytes_per_pixel;
}

fn draw_pixel(x: u32, y: u32, color: u32) callconv(.Inline) void {
    const offset = video_memory_offset(x, y);
    if (offset + 2 < buffer.len) {
        buffer[offset] = @truncate(u8, color);
        buffer[offset + 1] = @truncate(u8, color >> 8);
        buffer[offset + 2] = @truncate(u8, color >> 16);
        buffer_clean = false;
    }
}

fn draw_pixel_bgr(x: u32, y: u32, color: u32) callconv(.Inline) void {
    const offset = video_memory_offset(x, y);
    if (offset + 2 < buffer.len) {
        buffer[offset + 2] = @truncate(u8, color);
        buffer[offset + 1] = @truncate(u8, color >> 8);
        buffer[offset] = @truncate(u8, color >> 16);
        buffer_clean = false;
    }
}

pub fn draw_glyph(x: u32, y: u32, c: u8, fg_color: u32, bg_color: ?u32) void {
    var xi: usize = 0;
    var yi: usize = 0;
    const glyph = font.bitmaps[c - ' '];
    while (yi < font.height) {
        while (xi < font.width) {
            const o = (glyph[yi][xi / 8] << @intCast(u3, xi % 8)) & 0x80 != 0;
            if (o) {
                draw_pixel(x + xi, y + yi, fg_color);
            } else if (bg_color) |bgc| {
                draw_pixel(x + xi, y + yi, bgc);
            }
            xi += 1;
        }
        xi = 0;
        yi += 1;
    }
}

pub const Point = struct {
    x: u32,
    y: u32,
};

pub fn draw_string(x: u32, y: u32, s: []const u8, color: u32) Point {
    var x_offset = x;
    var y_offset = y;
    var max_x = x;
    for (s) |c| {
        if (c >= ' ' and c <= '~') {
            draw_glyph(x_offset, y_offset, c, color, null);
            x_offset += font.width;
            if (x_offset > max_x) {
                max_x = x_offset;
            }
        }
        if (c == '\n') {
            y_offset += font.height;
            x_offset = x;
        }
    }
    return Point{.x = max_x, .y = y_offset + font.height};
}

pub fn draw_string_continue(start: Point, s: []const u8, color: u32) Point {
    var x_offset = start.x;
    var y_offset = start.y;
    for (s) |c| {
        if (c >= ' ' and c <= '~') {
            draw_glyph(x_offset, y_offset, c, color, null);
            const next_offset = x_offset + font.width;
            if (next_offset >= mode.width) {
                y_offset += font.height;
                x_offset = 0;
            } else {
                x_offset = next_offset;
            }
        } else if (c == '\n') {
            y_offset += font.height;
            x_offset = 0;
        }
    }
    return Point{.x = x_offset, .y = y_offset};
}

pub fn draw_line(x1: u32, y1: u32, x2: u32, y2: u32, color: u32) void {
    const dx = x2 - x1;
    const dy = y2 - y1;
    if (dx > 0) {
        var x = x1;
        while (x <= x2) {
            draw_pixel(x, y1 + dy * (x - x1) / dx, color);
            x += 1;
        }
    } else {
        var y = y1;
        while (y <= y2) {
            draw_pixel(x1, y, color);
            y += 1;
        }
    }
}

pub fn draw_frame(x: u32, y: u32, w: u32, h: u32, color: u32) void {
    const x2 = x + w;
    const y2 = y + h;
    draw_line(x, y, x2, y, color);
    draw_line(x, y, x, y2, color);
    draw_line(x2, y, x2, y2, color);
    draw_line(x, y2, x2, y2, color);
}

pub fn draw_raw_image(data: []const u8, w: u32, x: u32, y: u32) void {
    var xi: u32 = 0;
    var yi: u32 = 0;
    const pixels = std.mem.bytesAsSlice(u32, data);
    for (pixels) |px| {
        draw_pixel_bgr(x + xi, y + yi, px);
        xi += 1;
        if (xi >= w) {
            yi += 1;
            xi = 0;
        }
    }
}

var buffer: []u8 = undefined;
var buffer_clean: bool = false;
var video_memory: []u8 = undefined;
var bytes_per_pixel: u32 = undefined;

pub fn fill_buffer(color: u32) void {
    if (bytes_per_pixel == 32) {
        const color64 = (@as(u64, color) << 32) + color;
        const b = Range.from_bytes(buffer).to_slice(u64);
        for (b) |*p| {
            p.* = color64;
        }
    } else {
        for (buffer) |*byte, i| {
            byte.* = @truncate(u8, color >> ((@truncate(u5, i) % 3)));
        }
    }
    buffer_clean = false;
}

// TODO: This could certainly be done faster, maybe through unrolling the loop
// some or CPU features like SSE.
pub fn flush_buffer() void {
    if (buffer_clean) return;
    const b = Range.from_bytes(buffer).to_slice(u64);
    const vm  = Range.from_bytes(video_memory).to_slice(u64);
    while ((putil.in8(0x03da) & 0x8) != 0) {}
    while ((putil.in8(0x03da) & 0x8) == 0) {}
    for (vm) |*p, i| {
        p.* = b[i];
    }
    buffer_clean = true;
}

const vbe_result_ptr: u16 = 0x8000;

const VbeFuncArgs = struct {
    bx: u16 = 0,
    cx: u16 = 0,
    di: u16 = 0,
    slow: bool = false,
};
fn vbe_func(name: []const u8, func_num: u16, args: VbeFuncArgs) bool {
    var params = bios_int.Params{
        .interrupt = 0x10,
        .eax = func_num,
        .ebx = args.bx,
        .ecx = args.cx,
        .edi = args.di,
        .slow = args.slow,
    };
    bios_int.run(&params) catch {
        print.format("   - vbe_func: {}: bios_int.run failed\n", .{name});
        return false;
    };
    if (@truncate(u16, params.eax) != 0x4f) {
        print.format("   - vbe_func: {}: failed, eax: {:x}\n", .{name, params.eax});
        return false;
    }
    return true;
}

fn get_vbe_info() ?*const Info {
    const vbe2 = "VBE2"; // Set the interface to use VBE Version 2
    _ = utils.memory_copy_truncate(@intToPtr([*]u8, vbe_result_ptr)[0..vbe2.len], vbe2);
    return if (vbe_func("get_vbe_info", 0x4f00, .{
        .di = vbe_result_ptr
    })) @intToPtr(*const Info, vbe_result_ptr) else null;
}

fn get_mode_info(mode_number: u16) ?*const Mode {
    return if (vbe_func("get_mode_info", 0x4f01, .{
        .cx = mode_number,
        .di = vbe_result_ptr
    })) @intToPtr(*const Mode, vbe_result_ptr) else null;
}

fn set_mode() void {
    vbe_setup = vbe_func("set_mode", 0x4f02, .{
        .bx = mode_id.? | 0x4000, // Use Linear Buffer
        .slow = true,
    });
}

pub fn init() void {
    if (!build_options.vbe) {
        return;
    }

    print.string(" - See if we can use VESA graphics..\n");

    // First see GRUB setup VBE
    if (multiboot.get_vbe_info()) |vbe| {
        print.string("   - Got VBE info from Multiboot...\n");
        info = @ptrCast(*Info, &vbe.control_info[0]).*;
        mode_id = vbe.mode;
        mode = @ptrCast(*Mode, &vbe.mode_info[0]).*;
        vbe_setup = true;
    }

    // Then see if we can set it up using the BIOS
    if (!vbe_setup) {
        // Get Info
        print.string("   - Trying to get VBE info directly from BIOS...\n");
        info = (get_vbe_info() orelse return).*;
        print.format("{}\n", .{info});
        if (info.get_version()) |version| {
            print.format("VERSION {}\n", .{version});
        }

        // Find the Mode We're Looking For
        const supported_modes = info.get_modes();
        defer kernel.alloc.free_array(supported_modes) catch unreachable;
        for (supported_modes) |supported_mode| {
            print.format("   - mode {:x}\n", .{supported_mode});
            const mode_ptr = get_mode_info(supported_mode) orelse return;
            print.format("     - {}x{}x{}\n", .{
                mode_ptr.width, mode_ptr.height, mode_ptr.bpp});
            if ((mode_ptr.attributes & (1 << 7)) == 0) {
                print.string("     - Non-linear, skipping...\n");
                continue;
            }
            if (mode_ptr.width == find_width and mode_ptr.height == find_height and
                    mode_ptr.bpp == find_bpp) {
                mode = mode_ptr.*;
                mode_id = supported_mode;
                break;
            }
        }
        if (mode_id == null) {
            print.string("   - Didn't Find VBE Mode\n");
            return;
        }

        // Set the Mode
        set_mode();
    }

    if (vbe_setup) {
        print.string("   - Got VBE info\n");

        if (info.get_version()) |version| {
            print.format("{}\n", .{version});
        }
        print.format("{}\n", .{info});
        print.format("{}\n", .{mode});

        // TODO
        // if (mode.bpp != 32 and mode.bpp != 16) {
        //     @panic("bpp is not 32 bits or 16 bits");
        // }
        bytes_per_pixel = mode.bpp / 8;

        const video_memory_size = @as(usize, mode.height) * @as(usize, mode.pitch);

        // TODO: Zig Bug? If catch is taken away Zig 0.5 fails to reject not
        // handling the error return. LLVM catches the mistake instead.
        print.format("vms: {}\n", .{video_memory_size});
        buffer = kernel.memory_mgr.big_alloc.alloc_array(u8, video_memory_size) catch {
            @panic("Couldn't alloc VBE Buffer");
        };
        const video_memory_range = kernel.memory_mgr.impl.get_unused_kernel_space(
                video_memory_size) catch {
            @panic("Couldn't Reserve VBE Buffer");
        };
        video_memory = @intToPtr([*]u8, video_memory_range.start)[0..video_memory_size];
        kernel.memory_mgr.impl.map(
                video_memory_range, mode.framebuffer, false) catch {
            @panic("Couldn't map VBE Buffer");
        };

        {
            fill_buffer(0xe8e6e3);
            const w = 301;
            const h = 170;
            const x = mode.width - w - 10;
            const y = mode.height - h - 10;
            const image align(@alignOf(u64)) = @embedFile("../../misc/dragon.img");
            draw_raw_image(image, w, x, y);
            _ = draw_string(x, y, " Georgios ", 0x181a1b);
            flush_buffer();
        }

        vbe_console.init(mode.width, mode.height);
        kernel.console = &vbe_console.console;
    } else {
        print.string(" - Could not init VBE graphics\n");
    }
}
