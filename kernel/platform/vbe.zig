// VESA BIOS Extensions (VBE) Version 2
//
// https://en.wikipedia.org/wiki/VESA_BIOS_Extensions
// https://wiki.osdev.org/VESA_Video_Modes

const multiboot = @import("multiboot.zig");
const pmemory = @import("memory.zig");
const putil = @import("util.zig");

const kutil = @import("../util.zig");
const print = @import("../print.zig");
const kmemory = @import("../memory.zig");
const font = @import("../font.zig");

const Info = packed struct {
    const magic_expected = "VESA";

    magic: [4]u8,
    version: u16,
    oem_ptr: [2]u16,
    capabilities: u32,
    video_mode_ptr: [2]u16,
    memory: u16,
    software_rev: u16,
    vendor: [2]u16,
    product_name: [2]u16,
    product_rev: [2]u16,

    const Version = enum (u8) {
        V1 = 1,
        V2 = 2,
        V3 = 3,
    };

    pub fn get_version(self: @This()) ?Version {
        return kutil.int_to_enum(Version, @intCast(u8, self.version >> 8));
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

var info: *Info = undefined;
var mode: *Mode = undefined;
var mem: *kmemory.Memory = undefined;

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
    const pixels = @bytesToSlice(u32, data[0..]);
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
    const color64 = (u64(color) << 32) + color;
    const b = @bytesToSlice(u64, buffer);
    for (b) |*p| {
        p.* = color64;
    }
    buffer_clean = false;
}

// TODO: This could certainly be done faster, maybe through unrolling the loop
// some or CPU features like SSE.
pub fn flush_buffer() void {
    if (buffer_clean) return;
    const b = @bytesToSlice(u64, buffer);
    const vm = @bytesToSlice(u64, video_memory);
    while ((putil.in8(0x03da) & 0x8) != 0) {}
    while ((putil.in8(0x03da) & 0x8) == 0) {}
    for (vm) |*p, i| {
        p.* = b[i];
    }
    buffer_clean = true;
}

pub fn init(memory: *kmemory.Memory) void {
    if (multiboot.get_vbe_info()) |vbe| {
        mem = memory;

        info = @ptrCast(*Info, &vbe.control_info[0]);
        if (info.get_version()) |version| {
            print.format("{}\n", version);
        }
        print.format("{}\n", info.*);
        mode = @ptrCast(*Mode, &vbe.mode_info[0]);
        print.format("{}\n", mode.*);

        if (mode.bpp != 32) {
            @panic("bpp is not 32bit");
        }
        bytes_per_pixel = mode.bpp / 8;

        const video_memory_size =
            @intCast(usize, u64(mode.width) * u64(mode.height) * bytes_per_pixel);

        // TODO: Zig Bug? If catch is taken away Zig 0.5 fails to reject not
        // handling the error return. LLVM catches the mistake instead.
        print.format("vms: {}\n", video_memory_size);
        buffer = mem.big_alloc.alloc_array(u8, video_memory_size) catch {
            @panic("Couldn't alloc VBE Buffer");
        };
        const video_memory_range =
                mem.platform_memory.get_unused_kernel_space(video_memory_size) catch {
            @panic("Couldn't Reserve VBE Buffer");
        };
        video_memory = @intToPtr([*]u8, video_memory_range.start)[0..video_memory_size];
        mem.platform_memory.map(video_memory_range, mode.framebuffer, false) catch {
            @panic("Couldn't map VBE Buffer");
        };

        {
            fill_buffer(0xe8e6e3);
            const w = 301;
            const h = 170;
            const x = mode.width - w - 10;
            const y = mode.height - h - 10;
            draw_raw_image(@embedFile("../../misc/dragon.img"), w, x, y);
            _ = draw_string(x, y, " Georgios ", 0x181a1b);
            flush_buffer();
        }
    } else {
        print.string("Missing VBE info from Multiboot. Could not init VBE.\n");
    }
}
