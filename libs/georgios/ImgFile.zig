const Self = @This();

const std = @import("std");

const utils = @import("utils");
const Point = utils.U32Point;

const io = @import("io.zig");
const system_calls = @import("system_calls.zig");

const Error = error {
    InvalidImgFile,
} || io.FileError;

file: *io.File,
buffer: []u8,
size: ?Point = null,
last: Point = .{},

fn parse_value(self: *Self, comptime Type: type) Error!Type {
    const bytes = self.buffer[0..@sizeOf(Type)];
    const got = try self.file.read(bytes);
    if (got != bytes.len) {
        return Error.InvalidImgFile;
    }
    return std.mem.bytesToValue(Type, bytes);
}

pub fn parse_header(self: *Self) Error!void {
    self.size = Point{
        .x = try self.parse_value(Point.Num),
        .y = try self.parse_value(Point.Num),
    };
}

pub fn draw(self: *Self, pos: Point) Error!void {
    if (self.size == null) {
        try self.parse_header();
    }

    while (true) {
        const got = try self.file.read(self.buffer[0..]);
        if (got > 0) {
            system_calls.vbe_draw_raw_image_chunk(
                self.buffer[0..got], self.size.?.x, pos, &self.last);
        } else {
            break;
        }
    }
}

