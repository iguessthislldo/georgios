// If vbe is setup, img takes a file produced by scripts/make_img.sh and the
// width and displays it on the screen until ESC is pressed.

const std = @import("std");
const georgios = @import("georgios");
comptime {_ = georgios;}
const utils = georgios.utils;
const Point = utils.U32Point;
const system_calls = georgios.system_calls;
const print_string = system_calls.print_string;
const print_uint = system_calls.print_uint;

var console = georgios.get_console_writer();
var buffer: [2048]u8 align(@alignOf(u64)) = undefined;
var alloc: std.mem.Allocator = undefined;

fn draw_image(path: []const u8, fullscreen: bool, overlay: bool,
        res: Point, at: ?utils.I32Point) u8 {
    // Open image file
    var file = georgios.fs.open(path, .{.ReadOnly = .{}}) catch |e| {
        print_string("img: open error: ");
        print_string(@errorName(e));
        print_string("\n");
        return 2;
    };

    var bmp_file = utils.Bmp(@TypeOf(file)).init(&file);
    bmp_file.read_header() catch |e| {
        print_string("img: failed to parse BMP header: ");
        print_string(@errorName(e));
        print_string("\n");
        return 2;
    };
    var image_size = bmp_file.image_size_pixels() catch @panic("?");

    // Figure out where the image is going.
    var last_scroll_count: u32 = undefined;
    var size: Point = .{};
    var cur_pos: Point = .{};
    var glyph_size: Point = .{};
    system_calls.get_vbe_console_info(&last_scroll_count, &size, &cur_pos, &glyph_size);
    var pos = Point{.x = 10, .y = 20};
    if (fullscreen) {
        if (!overlay) {
            // Reset Console
            system_calls.print_string("\x1bc");
        }
        system_calls.print_string("Loading Image...");
    } else if (at == null) {
        // Make sure the image appears between the two prompts, even if the
        // console scrolls.
        const prev_cur_y = glyph_size.y * cur_pos.y;
        const room = utils.align_up(image_size.y, glyph_size.y);
        const newlines: usize = room / glyph_size.y;
        var i: usize = 0;
        while (i < newlines) {
            print_string("\n");
            i += 1;
        }
        system_calls.get_vbe_console_info(&last_scroll_count, &size, &cur_pos, &glyph_size);
        pos = .{.y = prev_cur_y - last_scroll_count * glyph_size.y};
    }
    _ = res;
    if (at) |at_val| {
        const abs = at_val.abs().intCast(u32);
        pos = .{
            .x = if (at_val.x >= 0) abs.x else (res.x - image_size.x - abs.x),
            .y = if (at_val.y >= 0) abs.y else (res.y - image_size.y - abs.y),
        };
    }

    var exit_status: u8 = 0;
    // Draw the image on the screen
    var last = utils.U32Point{};
    var bmp_pos: usize = 0;
    while (bmp_file.read_bitmap(&bmp_pos, buffer[0..]) catch @panic("TODO")) |got| {
        system_calls.vbe_draw_raw_image_chunk(buffer[0..got], image_size.x, pos, &last);
    }
    system_calls.vbe_flush_buffer();
    file.close() catch |e| {
        print_string("img: file.close error: ");
        print_string(@errorName(e));
        print_string("\n");
        exit_status = 3;
    };

    return exit_status;
}

const StrList = std.ArrayList([]const u8);

fn handle_path(images_al: *StrList, path: []const u8) anyerror!void {
    // Is directory?
    var dir_file = georgios.fs.open(path, .{.ReadOnly = .{.dir = true}}) catch |e| {
        if (e == georgios.fs.Error.NotADirectory) {
            if (utils.ends_with(path, ".bmp")) {
                try images_al.append(try alloc.dupe(u8, path));
            }
        } else {
            try console.print("img: handle_path open error: {s}\n", .{@errorName(e)});
        }
        return;
    };
    defer dir_file.close() catch unreachable;
    var name_buffer: [256]u8 = undefined;
    while (true) {
        const read = dir_file.read(name_buffer[0..]) catch |e| {
            try console.print("img: handle_path read error: {s}\n", .{@errorName(e)});
            return;
        };
        if (read == 0) break;
        const name = name_buffer[0..read];
        if (utils.ends_with(name, ".bmp")) {
            var subpath_al = std.ArrayList(u8).init(alloc);
            defer subpath_al.deinit();
            try subpath_al.appendSlice(path);
            try subpath_al.append('/');
            try subpath_al.appendSlice(name);
            const subpath = subpath_al.toOwnedSlice();
            defer alloc.free(subpath);
            try handle_path(images_al, subpath);
        }
    }
}

fn parse_int_arg(i: usize, what: []const u8) ?i32 {
    if (i == georgios.proc_info.args.len) {
        try console.print("img: no argument passed to {s}\n", .{what});
        return null;
    }
    const arg = georgios.proc_info.args[i];
    return std.fmt.parseInt(i32, arg, 10) catch |e| {
        try console.print("img: invalid value {s} passed to {s}: {s}\n", .{arg, what, @errorName(e)});
        return null;
    };
}

pub fn main() !u8 {
    var arena = std.heap.ArenaAllocator.init(georgios.page_allocator);
    alloc = arena.allocator();
    defer arena.deinit();

    // Parse arguments
    var args_al = StrList.init(alloc);
    defer args_al.deinit();
    var fullscreen = true;
    var overlay = false;
    var at: ?utils.I32Point = null;
    var arg_i: usize = 0;
    var no_vbe = false; // No VBE is okay
    while (arg_i < georgios.proc_info.args.len) {
        const arg = georgios.proc_info.args[arg_i];
        if (utils.memory_compare(arg, "--embed")) {
            fullscreen = false;
        } else if (utils.memory_compare(arg, "-e")) {
            fullscreen = false;
        } else if (utils.memory_compare(arg, "--overlay")) {
            overlay = true;
        } else if (utils.memory_compare(arg, "--at")) {
            at = utils.I32Point{};
            arg_i += 1;
            at.?.x = parse_int_arg(arg_i, "--at X arg") orelse {
                return 1;
            };
            arg_i += 1;
            at.?.y = parse_int_arg(arg_i, "--at Y arg") orelse {
                return 1;
            };
        } else if (utils.memory_compare(arg, "--no-vbe")) {
            no_vbe = true;
        } else if (utils.starts_with(arg, "-")) {
            try console.print("img: invalid option: {s}\n", .{arg});
            return 1;
        } else {
            try args_al.append(arg);
        }
        arg_i += 1;
    }

    const res = system_calls.vbe_res();
    if (res == null) {
        if (no_vbe) {
            return 0;
        }
        print_string("img requires VBE graphics mode\n");
        return 1;
    }

    // Process args for image files
    var images_al = std.ArrayList([]const u8).init(alloc);
    for (args_al.items) |arg| {
        try handle_path(&images_al, arg);
    }
    const images = images_al.toOwnedSlice();
    defer alloc.free(images);
    if (images.len == 0) {
        print_string("img: requires image paths or directory paths with images in them\n");
        return 1;
    }

    if (fullscreen) {
        system_calls.print_string("\x1bc");
    }

    var i: usize = 0;
    while (i < images.len) {
        const exit_status = draw_image(images[i], fullscreen, overlay, res.?, at);
        if (exit_status != 0) {
            return exit_status;
        }

        if ((fullscreen and exit_status == 0 and !overlay) or
                (overlay and i == (images.len - 1))) {
            try console.print(
                "\x1b[0;0H({}/{}) images, press the ESC key to exit...", .{i + 1, images.len});

            // Wait for ESC key to be pressed.
            while (true) {
                if (system_calls.get_key(.Blocking)) |key_event| {
                    if (key_event.kind == .Pressed) {
                        switch (key_event.unshifted_key) {
                            .Key_CursorRight => {
                                if (!overlay and i < (images.len - 1)) {
                                    i += 1;
                                    break;
                                }
                            },
                            .Key_CursorLeft => {
                                if (!overlay and i > 0) {
                                    i -= 1;
                                    break;
                                }
                            },
                            .Key_Escape => {
                                // Reset Console
                                system_calls.print_string("\x1bc");
                                system_calls.exit(.{});
                            },
                            else => {},
                        }
                    }
                }
            }
        } else {
            i += 1;
        }
    }

    for (images) |image| {
        defer alloc.free(image);
    }

    return 0;
}
