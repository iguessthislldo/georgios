// If vbe is setup, img takes a file produced by scripts/make_img.sh and the
// width and displays it on the screen until ESC is pressed.

const std = @import("std");
const georgios = @import("georgios");
comptime {_ = georgios;}
const utils = georgios.utils;
const system_calls = georgios.system_calls;
const print_string = system_calls.print_string;

var buffer: [2048]u8 align(@alignOf(u64)) = undefined;

pub fn main() void {
    if (system_calls.vbe_res() == null) {
        print_string("img requires VBE graphics mode\n");
        return;
    }

    if (georgios.proc_info.args.len != 2) {
        print_string("img: requires image path and image width\n");
        return;
    }

    const width = std.fmt.parseUnsigned(u32, georgios.proc_info.args[1], 10) catch {
        print_string("img: image width is invalid\n");
        return;
    };

    var file = georgios.fs.open(georgios.proc_info.args[0]) catch |e| {
        print_string("img: open error: ");
        print_string(@errorName(e));
        print_string("\n");
        return;
    };

    // Reset Console
    system_calls.print_string("\x1bc");
    system_calls.print_string("Loading Image...");

    const pos = utils.U32Point{.x = 10, .y = 20};
    var last = utils.U32Point{};
    var got: usize = 1;
    var success = true;
    while (got > 0) {
        if (file.read(buffer[0..])) |g| {
            got = g;
        } else |e| {
            print_string("img: file.read error: ");
            print_string(@errorName(e));
            print_string("\n");
            got = 0;
            success = false;
        }
        if (got > 0) {
            system_calls.vbe_draw_raw_image_chunk(buffer[0..got], width, pos, last);
        }
    }
    system_calls.vbe_flush_buffer();

    if (success) {
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
        return;
    };
}
