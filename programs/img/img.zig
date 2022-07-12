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

var buffer: [2048]u8 align(@alignOf(u64)) = undefined;

pub fn main() u8 {
    const res = system_calls.vbe_res();
    if (res == null) {
        print_string("img requires VBE graphics mode\n");
        return 1;
    }

    // Parse arguments
    var path: ?[]const u8 = null;
    var fullscreen = true;
    for (georgios.proc_info.args) |arg| {
        if (utils.memory_compare(arg, "--embed")) {
            fullscreen = false;
        } else if (utils.memory_compare(arg, "-e")) {
            fullscreen = false;
        } else if (path == null) {
            path = arg;
        } else {
            print_string("Invalid argument: ");
            print_string(arg);
            print_string("\n");
        }
    }
    if (path == null) {
        print_string("img: requires image path\n");
        return 1;
    }

    // Open image file
    var file = georgios.fs.open(path.?) catch |e| {
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
        // Reset Console
        system_calls.print_string("\x1bc");
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

    // Draw the image on the screen
    var success = true;
    img_file.draw(pos) catch |e| {
        print_string("img: draw: ");
        print_string(@errorName(e));
        print_string("\n");
        success = false;
    };
    system_calls.vbe_flush_buffer();

    if (fullscreen and success) {
        system_calls.print_string("\x1b[0;0HPress the ESC key to exit...");

        // Wait for ESC key to be pressed.
        while (true) {
            if (system_calls.get_key(.Blocking)) |key_event| {
                if (key_event.kind == .Pressed and key_event.unshifted_key == .Key_Escape) {
                    break;
                }
            }
        }

        // Reset Console
        system_calls.print_string("\x1bc");
    }

    file.close() catch |e| {
        print_string("img: file.close error: ");
        print_string(@errorName(e));
        print_string("\n");
        return 3;
    };

    return if (success) 0 else 3;
}
