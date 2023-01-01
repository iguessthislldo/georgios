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

fn draw_image(path: []const u8, fullscreen: bool, overlay: bool) u8 {
    // Open image file
    var file = georgios.fs.open(path, .{.ReadOnly = .{}}) catch |e| {
        print_string("img: open error: ");
        print_string(@errorName(e));
        print_string("\n");
        return 2;
    };
    var img_file = georgios.ImgFile{.file = &file, .buffer = buffer[0..]};
    img_file.parse_header() catch |e| {
        print_string("img: invalid image file: ");
        print_string(@errorName(e));
        print_string("\n");
        return 2;
    };

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
    } else {
        // Make sure the image appears between the two prompts, even if the
        // console scrolls.
        const prev_cur_y = glyph_size.y * cur_pos.y;
        const room = utils.align_up(img_file.size.?.y, glyph_size.y);
        const newlines: usize = room / glyph_size.y;
        var i: usize = 0;
        while (i < newlines) {
            print_string("\n");
            i += 1;
        }
        system_calls.get_vbe_console_info(&last_scroll_count, &size, &cur_pos, &glyph_size);
        pos = .{.y = prev_cur_y - last_scroll_count * glyph_size.y};
    }

    var exit_status: u8 = 0;
    // Draw the image on the screen
    img_file.draw(pos) catch |e| {
        print_string("img: draw: ");
        print_string(@errorName(e));
        print_string("\n");
        exit_status = 3;
    };
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

fn handle_path(alloc: *std.mem.Allocator, images_al: *StrList, path: []const u8) anyerror!void {
    _ = alloc;
    // Is directory?
    var dir_file = georgios.fs.open(path, .{.ReadOnly = .{.dir = true}}) catch |e| {
        if (e == georgios.fs.Error.NotADirectory) {
            if (utils.ends_with(path, ".img")) {
                try console.print("IMG: {s}\n", .{path});
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
        if (utils.ends_with(name, ".img")) {
            var subpath_al = std.ArrayList(u8).init(alloc.*);
            defer subpath_al.deinit();
            try subpath_al.appendSlice(path);
            try subpath_al.append('/');
            try subpath_al.appendSlice(name);
            const subpath = subpath_al.toOwnedSlice();
            defer alloc.free(subpath);
            try handle_path(alloc, images_al, subpath);
        }
    }
}

pub fn main() !u8 {
    var arena = std.heap.ArenaAllocator.init(georgios.page_allocator);
    var alloc = arena.allocator();
    defer arena.deinit();

    const res = system_calls.vbe_res();
    if (res == null) {
        print_string("img requires VBE graphics mode\n");
        return 1;
    }

    // Parse arguments
    var args_al = StrList.init(alloc);
    defer args_al.deinit();
    var fullscreen = true;
    var overlay = false;
    for (georgios.proc_info.args) |arg| {
        if (utils.memory_compare(arg, "--embed")) {
            fullscreen = false;
        } else if (utils.memory_compare(arg, "-e")) {
            fullscreen = false;
        } else if (utils.memory_compare(arg, "--overlay")) {
            overlay = true;
        } else if (utils.starts_with(arg, "-")) {
            try console.print("img: invalid option: {s}\n", .{arg});
            return 1;
        } else {
            try args_al.append(arg);
        }
    }

    // Process args for image files
    var images_al = std.ArrayList([]const u8).init(alloc);
    for (args_al.items) |arg| {
        try handle_path(&alloc, &images_al, arg);
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
        const exit_status = draw_image(images[i], fullscreen, overlay);
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
