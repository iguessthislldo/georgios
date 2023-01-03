const std = @import("std");

const utils = @import("utils.zig");

const BaseError = error {
    EndOfStream, // TODO: Needed by skipBytes. Should be provided by Reader.Error? Zig Bug?
    BmpInvalidFile,
    BmpUnsupportedEncoding,
    BmpUnreadHeader,
    BmpAlreadyRead,
} || utils.Error;

const magic = "BM";

const BmpHeader = packed struct {
    magic0: u8 = magic[0],
    magic1: u8 = magic[1],
    file_size: u32,
    reserved: u32 = 0,
    data_offset: u32,

    fn check(self: *const BmpHeader) BaseError!void {
        const sz = @sizeOf(BmpHeader);
        if (self.magic0 != magic[0] or self.magic1 != magic[1] or
                self.file_size <= sz or self.data_offset <= sz or
                self.data_offset >= self.file_size) {
            return BaseError.BmpInvalidFile;
        }
    }
};

const Encoding = enum(u32) {
    Rgb = 0,
    RunLenEnc8 = 1,
    RunLenEnc16 = 2,
    Rgba = 3,
    _,
};

const DibHeader = packed struct {
    dib_header_size: u32 = @sizeOf(DibHeader),
    width: u32,
    height: u32,
    planes: u16,
    bits_per_pixel: u16,
    encoding: Encoding, // "compression"
    image_size: u32,
    x_pixels_per_meter: u32,
    y_pixels_per_meter: u32,
    color_table_count: u32,
    important_color_count: u32,

    fn check(self: *const DibHeader) BaseError!void {
        if (self.dib_header_size < @sizeOf(DibHeader) or self.width == 0 or self.height == 0 or
                self.planes == 0 or self.bits_per_pixel == 0) {
            return BaseError.BmpInvalidFile;
        }
        if (self.encoding != .Rgba) {
            // TODO: That's what Gimp and ImageMagick seem to produce
            return BaseError.BmpUnsupportedEncoding;
        }
        if (@intCast(usize, self.width) * self.height * self.bits_per_pixel / 8 != self.image_size) {
            // TODO: image_size might be 0?
            return BaseError.BmpInvalidFile;
        }
    }
};

pub fn Bmp(comptime ReaderType: type) type {
    return struct {
        const Self = @This();
        pub const Error = BaseError || ReaderType.Error;

        bytes_read: usize = 0,
        headers_read: bool = false,
        bitmap_read: bool = false,
        bmp_header: BmpHeader = undefined,
        dib_header: DibHeader = undefined,

        fn read_header_i(self: *Self, comptime Type: type, value: *Type,
                reader: ReaderType) Error!*Type {
            const count = try reader.read(std.mem.asBytes(value));
            self.bytes_read += count;
            if (count < @sizeOf(Type)) {
                return Error.BmpInvalidFile;
            }
            return value;
        }

        pub fn read_header(self: *Self, reader: ReaderType) Error!void {
            if (self.headers_read) return Error.BmpAlreadyRead;
            try (try self.read_header_i(BmpHeader, &self.bmp_header, reader)).check();
            try (try self.read_header_i(DibHeader, &self.dib_header, reader)).check();
            self.headers_read = true;
        }

        pub fn image_size_pixels(self: *const Self) Error!utils.U32Point {
            if (!self.headers_read) return Error.BmpUnreadHeader;
            return utils.U32Point{.x = self.dib_header.width, .y = self.dib_header.height};
        }

        pub fn image_size_bytes(self: *const Self) Error!usize {
            if (!self.headers_read) return Error.BmpUnreadHeader;
            return self.dib_header.image_size;
        }

        pub fn read_bitmap(self: *Self, reader: ReaderType, dest: []u8) Error!usize {
            if (self.bitmap_read) return Error.BmpAlreadyRead;
            const expected = try self.image_size_bytes();
            if (dest.len < expected) {
                return Error.NotEnoughDestination;
            }
            try reader.skipBytes(self.bmp_header.data_offset - self.bytes_read, .{});
            const count = try reader.read(dest[0..expected]);
            if (count != expected) {
                return Error.BmpInvalidFile;
            }
            self.bytes_read += count;
            self.bitmap_read = true;
            return count;
        }
    };
}

test "read test.bmp" {
    var ta = utils.TestAlloc{};
    defer ta.deinit(.Panic);
    errdefer ta.deinit(.NoPanic);
    const alloc = ta.alloc();
    _ = alloc;

    var file = try std.fs.cwd().openFile("misc/test.bmp", .{.read = true});
    defer file.close();

    var bmp = Bmp(@TypeOf(file).Reader){};
    const reader = file.reader();
    try bmp.read_header(reader);
    // std.debug.print("BMP STRUCT: {}\n", .{bmp});

    var bitmap = [_]u8{0} ** 1024;
    _ = try bmp.read_bitmap(reader, bitmap[0..]);
    // std.debug.print("BITMAP: {}\n", .{utils.fmt_dump_hex(bitmap[0..])});

    // TODO: Fix color and orientation
    var expected_ascii =
        "                " ++
        "     @@@@@@     " ++
        "    @@@@@@@@    " ++
        "   @@@@@@@@@@   " ++
        "  @@@------@@@  " ++
        " @@@@@@@@@@@@@@ " ++
        " @@@@@@@@@@@@@@ " ++
        " @@@@@@@@@@@@@@ " ++
        " @@@-@@@@-@@@@@ " ++
        " @@@---@@---@@@ " ++
        " @@@@-@@@@-@@@@ " ++
        "  @@@@@@@@@@@@  " ++
        "   @@@@@@@@@@   " ++
        "    @@@@@@@@    " ++
        "     @@@@@@     " ++
        "                ";
    var expected: [1024]u8 = undefined;
    for (expected_ascii) |ascii_pixel, i| {
        var e = expected[i * 4..(i + 1) * 4];
        switch (ascii_pixel) {
            ' ' => { // Transparent
                e[0] = 0;
                e[1] = 0;
                e[2] = 0;
                e[3] = 0;
            },
            '@' => { // Yellow
                e[0] = 0;
                e[1] = 0xff;
                e[2] = 0xff;
                e[3] = 0xff;
            },
            '-' => { // Black
                e[0] = 0;
                e[1] = 0;
                e[2] = 0;
                e[3] = 0xff;
            },
            else => @panic("Unexpected \"expected\" ASCII"),
        }
    }

    if (false) {
        for (std.mem.bytesAsSlice(u32, bitmap[0..])) |p, i| {
            const c: u8 = switch (p) {
                0 => ' ',
                0xff000000 => '-',
                0xffffff00 => '@',
                else => {
                    std.debug.print("GOT {x}", .{p});
                    @panic("??");
                },
            };
            std.debug.print("{c}", .{c});
            if (@mod(i, 16) == 0) {
                std.debug.print("\n", .{});
            }
        }
    }

    try utils.expect_equal_bytes(expected[0..], bitmap[0..]);
}
