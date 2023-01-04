// VESA BIOS Extensions (VBE) Version 2
//
// https://en.wikipedia.org/wiki/VESA_BIOS_Extensions
// https://wiki.osdev.org/VESA_Video_Modes

const std = @import("std");
const build_options = @import("build_options");

const utils = @import("utils");
const U32Point = utils.U32Point;
pub const Box = utils.Box(u32, u32);

const multiboot = @import("multiboot.zig");
const pmemory = @import("memory.zig");
const putil = @import("util.zig");
const bios_int = @import("bios_int.zig");
const vbe_console = @import("vbe_console.zig");

const kernel = @import("root").kernel;
const print = kernel.print;
const kmemory = kernel.memory;
const Range = kmemory.Range;
const BitmapFont = kernel.BitmapFont;

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

pub fn get_res() ?U32Point {
    return if (vbe_setup) .{.x = mode.width, .y = mode.height} else null;
}

fn video_memory_offset(x: u32, y: u32) callconv(.Inline) u32 {
    return y * mode.pitch + x * bytes_per_pixel;
}

fn blend(dest: *u8, color: u8, alpha: u8) callconv(.Inline) void {
    dest.* = @truncate(u8, (@intCast(u32, color) * alpha +
        @intCast(u32, dest.*) * (0xff - alpha)) >> 8);
}

fn draw_pixel(x: u32, y: u32, color: u32) callconv(.Inline) void {
    const offset = video_memory_offset(x, y);
    if (offset + 2 < buffer.len) {
        const alpha = @truncate(u8, color >> 24);
        blend(&buffer[offset], @truncate(u8, color), alpha);
        blend(&buffer[offset + 1], @truncate(u8, color >> 8), alpha);
        blend(&buffer[offset + 2], @truncate(u8, color >> 16), alpha);
        buffer_clean = false;
    }
}

pub fn draw_glyph(font: *const BitmapFont, x: u32, y: u32, codepoint: u32,
        fg_color: u32, bg_color: u32) void {
    const glyph_holder = font.get(codepoint);
    var xp = x;
    var xe = x + font.bdf_font.bounds.size.x;
    var yp = y;
    var pixit = glyph_holder.iter_pixels();
    while (pixit.next_pixel()) |is_filled| {
        draw_pixel(xp, yp, if (is_filled) fg_color else bg_color);
        xp += 1;
        if (xp >= xe) {
            xp = x;
            yp += 1;
        }
    }
}

pub fn draw_line(a: U32Point, b: U32Point, color: u32) void {
    const d = b.minus_point(a);
    if (d.x > 0) {
        var x = a.x;
        while (x <= b.x) {
            draw_pixel(x, a.y + d.y * (x - a.x) / d.x, color);
            x += 1;
        }
    } else {
        var y = a.y;
        while (y <= b.y) {
            draw_pixel(a.x, y, color);
            y += 1;
        }
    }
}

pub fn draw_box(box: Box, color: u32) void {
    // a > b
    // V   V
    // c > d
    const a = box.pos;
    const d = box.pos.plus_point(box.size);
    const b = .{.x = d.x, .y = a.y};
    const c = .{.x = a.x, .y = d.y};
    draw_line(a, b, color);
    draw_line(a, c, color);
    draw_line(b, d, color);
    draw_line(c, d, color);
}

pub fn draw_raw_image_chunk(data: []const u8, w: u32, pos: *const U32Point, last: *U32Point) void {
    const pixels = std.mem.bytesAsSlice(u32, data);
    for (pixels) |px| {
        draw_pixel(pos.x + last.x, pos.y + last.y, px);
        last.x += 1;
        if (last.x >= w) {
            last.y += 1;
            last.x = 0;
        }
    }
}

pub fn draw_raw_image(data: []const u8, w: u32, x: u32, y: u32) void {
    var last = U32Point{};
    draw_raw_image_chunk(data, w, .{.x = x, .y = y}, &last);
}

var buffer: []u8 = undefined;
var buffer_clean: bool = false;
var video_memory: []u8 = undefined;
var bytes_per_pixel: u32 = undefined;

pub fn fill_buffer(color: u32) void {
    var y: u32 = 0;
    while (y < mode.height) {
        var x: u32 = 0;
        while (x < mode.width) {
            draw_pixel(x, y, color);
            x += 1;
        }
        y += 1;
    }
    buffer_clean = false;
}

pub fn scroll_buffer(rows: u32, color: u32) void {
    // Move everthing in the buffer up
    buffer_clean = false;
    var dst_offset: usize = 0;
    var src_offset: usize = rows * mode.pitch;
    const end_src_offset = @as(usize, mode.height) * mode.pitch;
    const row_size = @as(usize, mode.width) * bytes_per_pixel;
    while (src_offset < end_src_offset) {
        const dst = buffer[dst_offset..dst_offset + row_size];
        const src = buffer[src_offset..src_offset + row_size];
        for (dst) |*p, i| {
            p.* = src[i];
        }
        dst_offset += mode.pitch;
        src_offset += mode.pitch;
    }

    // Fill in the "new" pixels
    var y: u32 = mode.height - rows;
    while (y < mode.height) {
        var x: u32 = 0;
        while (x < mode.width) {
            draw_pixel(x, y, color);
            x += 1;
        }
        y += 1;
    }
}

fn buffer_sync() callconv(.Inline) void {
    while ((putil.in8(0x03da) & 0x8) != 0) {}
    while ((putil.in8(0x03da) & 0x8) == 0) {}
}

// TODO: This could certainly be done faster, maybe through unrolling the loop
// some or CPU features like SSE.
pub fn flush_buffer() void {
    if (buffer_clean) return;
    const b = Range.from_bytes(buffer).to_slice(u64);
    const vm  = Range.from_bytes(video_memory).to_slice(u64);
    buffer_sync();
    for (vm) |*p, i| {
        p.* = b[i];
    }
    buffer_clean = true;
}

pub fn flush_buffer_area(area: Box) void {
    buffer_sync();
    var offset = video_memory_offset(area.pos.x, area.pos.y);
    var row = area.pos.y;
    const end = area.pos.y + area.size.y;
    const row_size = area.size.x * bytes_per_pixel;
    while (row < end) {
        const row_end = offset + row_size;
        const b = buffer[offset..row_end];
        for (video_memory[offset..row_end]) |*p, i| {
            p.* = b[i];
        }
        offset += mode.pitch;
        row += 1;
    }
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

        kernel.builtin_font.init(
            &kernel.builtin_font_data.bdf,
            kernel.builtin_font_data.glyph_indices[0..],
            kernel.builtin_font_data.bitmaps[0..])
                catch @panic("builtin_font.init failed");
        vbe_console.init(mode.width, mode.height, &kernel.builtin_font);
        kernel.console = &vbe_console.console;
    } else {
        print.string(" - Could not init VBE graphics\n");
    }
}
