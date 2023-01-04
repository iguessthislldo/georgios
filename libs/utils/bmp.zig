// Read the BMP/Windows bitmap file format and convert the bitmap data to a
// form that can be put in a display buffer.
//
// For reference:
//   https://en.wikipedia.org/wiki/BMP_file_format

const std = @import("std");

const utils = @import("utils.zig");

const BaseError = error {
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

// The "Device-independent bitmap" header apparently is a separate struct in
// the Windows C API.
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

pub fn Bmp(comptime File: type) type {
    return struct {
        const Self = @This();
        const Reader = File.Reader;
        const SeekableStream = File.SeekableStream;
        pub const Error = BaseError || Reader.Error || SeekableStream.SeekError;

        reader: Reader,
        seekable_stream: SeekableStream,
        headers_read: bool = false,
        bmp_header: BmpHeader = undefined,
        dib_header: DibHeader = undefined,

        pub fn init(file: *File) Self {
            return .{
                .reader = file.reader(),
                .seekable_stream = file.seekableStream(),
            };
        }

        fn read_header_i(self: *Self, comptime Type: type, value: *Type) Error!*Type {
            const count = try self.reader.read(std.mem.asBytes(value));
            if (count < @sizeOf(Type)) {
                return Error.BmpInvalidFile;
            }
            return value;
        }

        pub fn read_header(self: *Self) Error!void {
            try self.seekable_stream.seekTo(0);
            try (try self.read_header_i(BmpHeader, &self.bmp_header)).check();
            try (try self.read_header_i(DibHeader, &self.dib_header)).check();
            self.headers_read = true;
        }

        pub fn image_size_pixels(self: *Self) Error!utils.U32Point {
            if (!self.headers_read) try self.read_header();
            return utils.U32Point{.x = self.dib_header.width, .y = self.dib_header.height};
        }

        pub fn image_size_bytes(self: *Self) Error!utils.U32Point {
            return (try self.image_size_pixels()).multiply(self.dib_header.bits_per_pixel).divide(8);
        }

        pub fn image_size_bytes_total(self: *Self) Error!usize {
            if (!self.headers_read) try self.read_header();
            return self.dib_header.image_size;
        }

        pub fn read_bitmap(self: *Self, pos: *usize, buffer: []u8) Error!?usize {
            if (buffer.len == 0) {
                return Error.NotEnoughDestination;
            }

            // NOTE: BMP data is "bottom-up":
            // https://devblogs.microsoft.com/oldnewthing/20210525-00/?p=105250
            // Each row is in the expected order from left lsb to right msb,
            // but the most bottom row is first in the bitmap data of the file.
            // We need to supply the expected order to the buffer.
            // TODO: Each row is aligned to 4 bytes. The padding for this would
            // need to be omitted from the output. Right now though we only
            // support 32 bpp RGBA, which won't have the padding.

            const total_expected = try self.image_size_bytes_total();
            const width: usize = self.dib_header.width * self.dib_header.bits_per_pixel / 8;
            const data_end: usize = self.bmp_header.data_offset + total_expected;
            var got: usize = 0;
            while (got < buffer.len and pos.* < total_expected) {
                const row = pos.* / width;
                const col = @mod(pos.*, width);
                const seek_to = data_end - width * (row + 1) + col;
                const count = @minimum(width - col, buffer.len - got);
                try self.seekable_stream.seekTo(seek_to);
                if ((try self.reader.read(buffer[got..got + count])) != count) {
                    return Error.BmpInvalidFile;
                }
                got += count;
                pos.* += count;
            }

            return if (got == 0) null else got;
        }
    };
}

test "read test.bmp" {
    var file = try std.fs.cwd().openFile("misc/test.bmp", .{.read = true});
    defer file.close();

    var bmp = Bmp(@TypeOf(file)).init(&file);
    try bmp.read_header();
    // std.debug.print("BMP STRUCT: {}\n", .{bmp});

    var bitmap = [_]u8{0} ** 1024;
    var buffer: [129]u8 = undefined;
    var pos: usize = 0;
    while (try bmp.read_bitmap(&pos, buffer[0..])) |got| {
        for (buffer[0..got]) |byte, i| {
            bitmap[pos - got + i] = byte;
        }
    }
    // std.debug.print("BITMAP: {}\n", .{utils.fmt_dump_hex(bitmap[0..])});

    var expected_ascii =
        "                " ++
        "     @@@@@@     " ++
        "    @@@@@@@@    " ++
        "   @@@@@@@@@@   " ++
        "  @@@@@@@@@@@@  " ++
        " @@@@-@@@@-@@@@ " ++
        " @@@---@@---@@@ " ++
        " @@@-@@@@-@@@@@ " ++
        " @@@@@@@@@@@@@@ " ++
        " @@@@@@@@@@@@@@ " ++
        " @@@@@@@@@@@@@@ " ++
        "  @@@------@@@  " ++
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
                    std.debug.print("GOT pixel value {x}\n", .{p});
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
