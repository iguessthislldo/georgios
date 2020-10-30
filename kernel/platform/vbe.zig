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

// TODO: Better Memory Access than the Temp Page, Buffering
fn draw_pixel(x: u32, y: u32, color: u32) void {
    const pmem = &mem.platform_memory;
    const address = y * u32(mode.pitch) + x * u32(mode.bpp / 8) + mode.framebuffer;
    pmem.map_virtual_page(address);
    const vaddress = pmem.virtual_page_address + address % pmemory.page_size;
    const pixel = @intToPtr(*u32, vaddress);
    pixel.* = color;
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

const colors = [_]u32{
    16711680,
    16727296,
    16742912,
    16758528,
    16774144,
    13369088,
    9371392,
    5373696,
    1376000,
    65320,
    65382,
    65443,
    65504,
    57599,
    41983,
    26367,
    10495,
    1310975,
    5308671,
    9306367,
    13369599,
    16711924,
    16711863,
    16711802,
    16711741,
    16711680,
};

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

        draw_line(0, 0, mode.width, mode.height, 0x0000FFFF);

        const p = draw_string(75, 75,
            "And on the pedestal, these words appear:\n" ++
            "My name is Ozymandias, King of Kings;\n" ++
            "Look on my Works, ye Mighty, and despair!\n" ++
            "Nothing beside remains. Round the decay\n" ++
            "Of that colossal Wreck, boundless and bare\n" ++
            "The lone and level sands stretch far away.",
            0x00FF00FF);

        draw_frame(75, 75, p.x - 75, p.y - 75, 0xFFFF00);
    } else {
        print.string("Missing VBE info from Multiboot. Could not init VBE.\n");
    }
}
