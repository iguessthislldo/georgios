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

const kernel = @import("../kernel.zig");
const print = @import("../print.zig");
const kmemory = @import("../memory.zig");
const Range = kmemory.Range;
const font = @import("../font.zig");

// TODO Make these not fixed
// 1024x768x32
const find_width = 1024;
const find_height = 768;
const find_bpp = 32;

const RealModePtr = packed struct {
    offset: u16,
    segment: u16,

    pub fn get(self: *const RealModePtr) u32 {
        return self.segment * 0x10 + self.offset;
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
        const modes = kernel.memory.small_alloc.alloc_array(u16, mode_count) catch
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

inline fn video_memory_offset(x: u32, y: u32) u32 {
    return y * mode.pitch + x * bytes_per_pixel;
}

inline fn draw_pixel(x: u32, y: u32, color: u32) void {
    const offset = video_memory_offset(x, y);
    if (offset + 2 < buffer.len) {
        buffer[offset] = @truncate(u8, color);
        buffer[offset + 1] = @truncate(u8, color >> 8);
        buffer[offset + 2] = @truncate(u8, color >> 16);
        buffer_clean = false;
    }
}

inline fn draw_pixel_bgr(x: u32, y: u32, color: u32) void {
    const offset = video_memory_offset(x, y);
    if (offset + 2 < buffer.len) {
        buffer[offset + 2] = @truncate(u8, color);
        buffer[offset + 1] = @truncate(u8, color >> 8);
        buffer[offset] = @truncate(u8, color >> 16);
        buffer_clean = false;
    }
}

fn draw_glyph(x: u32, y: u32, c: u8, color: u32) void {
    var xi: usize = 0;
    var yi: usize = 0;
    const glyph = font.bitmaps[c - ' '];
    while (yi < font.height) {
        while (xi < font.width) {
            const o = (glyph[yi][xi / 8] << @intCast(u3, xi % 8)) & 0x80 != 0;
            if (o) {
                draw_pixel(x + xi, y + yi, color);
            }
            xi += 1;
        }
        xi = 0;
        yi += 1;
    }
}

const Point = struct {
    x: u32,
    y: u32,
};

fn draw_string(x: u32, y: u32, s: []const u8, color: u32) Point {
    var x_offset = x;
    var y_offset = y;
    var max_x = x;
    for (s) |c, i| {
        if (c >= ' ' and c <= '~') {
            draw_glyph(x_offset, y_offset, c, color);
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

fn draw_string_continue(start: Point, s: []const u8, color: u32) Point {
    var x_offset = start.x;
    var y_offset = start.y;
    for (s) |c, i| {
        if (c >= ' ' and c <= '~') {
            draw_glyph(x_offset, y_offset, c, color);
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

fn draw_line(x1: u32, y1: u32, x2: u32, y2: u32, color: u32) void {
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

fn draw_frame(x: u32, y: u32, w: u32, h: u32, color: u32) void {
    const x2 = x + w;
    const y2 = y + h;
    draw_line(x, y, x2, y, color);
    draw_line(x, y, x, y2, color);
    draw_line(x2, y, x2, y2, color);
    draw_line(x, y2, x2, y2, color);
}

fn draw_raw_image(data: []const u8, w: u32, x: u32, y: u32) void {
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

fn fill_buffer(color: u32) void {
    const color64 = (@as(u64, color) << 32) + color;
    const b = Range.from_bytes(buffer).to_slice(u64);
    for (b) |*p| {
        p.* = color64;
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

    // Then see if we can set it up usng BIOS
    if (!vbe_setup) {
        // Get Info
        print.string("   - Trying to get VBE info directly from BIOS...\n");
        const result_ptr: u32 = 0x1000;
        var params = bios_int.Params{
            .interrupt = 0x10,
            .eax = 0x4f00,
            .edi = result_ptr,
        };
        bios_int.run(&params) catch {
            print.string("   - get info bios_int.run failed\n");
            return;
        };
        if (params.eax != 0x4f) {
            print.format("   - get info failed eax: {}\n", .{params.eax});
            return;
        }
        info = @intToPtr(*Info, result_ptr).*;
        print.format("{}\n", .{info});

        // Find the Mode We're Looking For
        const supported_modes = info.get_modes();
        defer kernel.memory.small_alloc.free_array(supported_modes) catch unreachable;
        for (supported_modes) |supported_mode| {
            print.format("   - mode {}\n", .{supported_mode});
            params.eax = 0x4f01;
            params.ecx = supported_mode;
            params.edi = result_ptr;
            bios_int.run(&params) catch {
                print.string("   - get mode bios_int.run failed\n");
                return;
            };
            if (params.eax != 0x4f) {
                print.format("   - get mode details failed eax: {}\n", .{params.eax});
                return;
            }
            const mode_ptr = @intToPtr(*const Mode, result_ptr);
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
            print.string("     - Didn't Find VBE Mode\n");
            return;
        }

        // Set the Mode
        params.eax = 0x4f02;
        params.ebx = mode_id.? | 0x4000; // Use Linear Buffer
        params.slow = true;
        bios_int.run(&params) catch {
            print.string("   - set mode bios_int.run failed\n");
            return;
        };
        if (params.eax != 0x4f) {
            print.format("   - set mode failed eax: {}\n", .{params.eax});
            return;
        }

        vbe_setup = true;
    }

    if (vbe_setup) {
        print.string("   - Got VBE info\n");

        if (info.get_version()) |version| {
            print.format("{}\n", .{version});
        }
        print.format("{}\n", .{info});
        print.format("{}\n", .{mode});

        if (mode.bpp != 32) {
            @panic("bpp is not 32bit");
        }
        bytes_per_pixel = mode.bpp / 8;

        const video_memory_size =
            @intCast(usize, @as(u64, mode.width) * @as(u64, mode.height) * bytes_per_pixel);

        // TODO: Zig Bug? If catch is taken away Zig 0.5 fails to reject not
        // handling the error return. LLVM catches the mistake instead.
        print.format("vms: {}\n", .{video_memory_size});
        buffer = kernel.memory.big_alloc.alloc_array(u8, video_memory_size) catch {
            @panic("Couldn't alloc VBE Buffer");
        };
        const video_memory_range = kernel.memory.platform_memory.get_unused_kernel_space(
                video_memory_size) catch {
            @panic("Couldn't Reserve VBE Buffer");
        };
        video_memory = @intToPtr([*]u8, video_memory_range.start)[0..video_memory_size];
        kernel.memory.platform_memory.map(video_memory_range, mode.framebuffer, false) catch {
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
    } else {
        print.string(" - Missing VBE info from Multiboot. Could not init VBE.\n");
    }
}
