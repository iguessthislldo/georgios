// Parser for Bitmap Distribution Format (BDF) monospace fonts. It skips a good
// chunk of BDF spec details because they don't matter for monospace fonts or
// at least didn't seem to matter for the monospace fonts I've seen so far.
//
// For reference:
//   https://en.wikipedia.org/wiki/Glyph_Bitmap_Distribution_Format
//   https://adobe-type-tools.github.io/font-tech-notes/pdfs/5005.BDF_Spec.pdf

const Self = @This();

const std = @import("std");

const utils = @import("utils.zig");
const WordIterator = utils.WordIterator;
const Box = utils.Box;
const streq = utils.memory_compare;

const Bounds = Box(i16, u16);

pub const Error = error {
    BdfBadKeyword,
    BdfMissingValue,
    BdfBadValue,
    BdfBadPropCount,
    BdfBadGlyphCount,
    BdfBadBitmap,
    BdfMissingBuffer,
    BdfBufferTooSmall,
    BdfMissingDefaultCodepoint,
} || utils.Error;

fn get_row_size(width: usize) usize {
    return utils.align_up(width, 8) / 8;
}

pub fn get_glyph_size(size: Bounds.Size) usize {
    return get_row_size(size.x) * size.y;
}

fn get_byte_shift(from_left: usize) u3 {
    return @truncate(u3, 7 - from_left % 8);
}

fn set_bit(byte: *u8, from_left: usize, value: bool) void {
    const bit = @as(u8, 1) << get_byte_shift(from_left);
    if (value) {
        byte.* = byte.* | bit;
    } else {
        byte.* = byte.* & ~bit;
    }
}

fn get_bit(byte: u8, from_left: usize) bool {
    return (byte >> get_byte_shift(from_left)) & 1 == 1;
}

name: utils.FixedString(128) = .{}, // FONT_NAME Property
bounds: Bounds = .{}, // FONTBOUNDINGBOX
glyph_count: u32 = 0, // CHARS
default_codepoint: u32 = '?', // DEFAULT_CHAR
found_default_codepoint: bool = false,

pub fn glyph_size(self: *const Self) usize {
    return get_glyph_size(self.bounds.size);
}

pub fn required_buffer_size(self: *const Self) usize {
    return @as(usize, self.glyph_count) * self.glyph_size();
}

pub fn glyph_pixel_count(self: *const Self) usize {
    return self.bounds.size.x * self.bounds.size.y;
}

pub fn total_pixel_count(self: *const Self) usize {
    return self.glyph_pixel_count() * self.glyph_count;
}

pub const Glyph = struct {
    index: usize,
    size: Bounds.Size,
    bitmap_offset: usize,
    bitmap_size: usize,
    name: ?[]const u8 = null, // STARTFONT
    codepoint: ?u32 = null, // ENCODING
    bounds: Bounds = .{}, // BBX

    pub fn new(font: *const Self, index: usize) Glyph {
        return .{
            .index = index,
            .bitmap_offset = index * font.glyph_size(),
            .bitmap_size = font.glyph_size(),
            .size = font.bounds.size,
        };
    }

    fn get_bitmap(self: *const Glyph, buffer: []u8) []u8 {
        return buffer[self.bitmap_offset..self.bitmap_offset + self.bitmap_size];
    }

    fn get_const_bitmap(self: *const Glyph, buffer: []const u8) []const u8 {
        return buffer[self.bitmap_offset..self.bitmap_offset + self.bitmap_size];
    }

    pub fn get_byte_offset(self: *const Glyph, row: usize, col: usize) usize {
        const row_size = get_row_size(self.size.x);
        return row * row_size + col / 8;
    }

    pub const Iterator = struct {
        glyph: *const Glyph,
        buffer: []const u8,
        row: usize = 0,
        col: usize = 0,
        new_row: bool = false,

        pub fn next_pixel(self: *Iterator) ?bool {
            if (self.row >= self.glyph.size.y) {
                return null;
            }
            const bitmap = self.glyph.get_const_bitmap(self.buffer);
            const byte = bitmap[self.glyph.get_byte_offset(self.row, self.col)];
            const filled = get_bit(byte, self.col);
            self.col += 1;
            self.new_row = self.col >= self.glyph.size.x;
            if (self.new_row) {
                self.col = 0;
                self.row += 1;
            }
            return filled;
        }
    };

    pub fn iter_pixels(self: *const Glyph, buffer: []const u8) Iterator {
        return .{.glyph = self, .buffer = buffer};
    }

    pub fn preview(self: *const Glyph, bitmap_buffer: []const u8, output_buffer: []u8) Error![]u8 {
        const size = (@as(usize, self.size.x) + 1) * @as(usize, self.size.y);
        if (output_buffer.len < size) {
            return Error.NotEnoughDestination;
        }
        const output = output_buffer[0..size];
        var pixit = self.iter_pixels(bitmap_buffer);
        var i: usize = 0;
        while (pixit.next_pixel()) |filled| {
            output[i] = if (filled) '#' else '.';
            i += 1;
            if (pixit.new_row) {
                output[i] = '\n';
                i += 1;
            }
        }
        return output;
    }
};

// Thinking out how to convert the compact bitmap to a full bitmap.
//
// An example font is 6x9 pixels and can extend two pixels below the baseline.
// In BDF, this means the "FONTBOUNDINGBOX" is "6 9 0 -2". All glyphs should be
// able to fit in this box:
//
// |..... "+" is origin and the horizontal line is the baseline.
// |.....
// |..... All the glyphs should be able to be converted into a bitmap image
// |..... from the font bitmap data and then copied into video memory.
// |.....
// |..... BDF bitmap data doesn't have to fill out the entire font bounding
// +----- box. We will have to position the glyph correctly.
// |.....
// |.....
//
// Glyph bounding box (BBw(3), BBh(7), BBx(2), BBy(-1)) relative to font
// bounding box (FBBw(6), FBBh(9), FBBx(0), FBBy(-2)) (shown widened x2):
//
// |FBBx
// ←BBx→←BBw→
// ←---FBBw---→
// | . . . . .     ↑FBBh  Empty rows before bitmap = FBBh + FBBy - BBh - BBy
// | . # # # .     |↑      Empty rows after bitmap = BBy - FBBy
// | . # # # .     ||  Empty columns before bitmap = BBx - FBBx
// | . # # # .     ||   Empty columns after bitmap = FBBw + FBBx - BBw - BBx
// | . # # # .     ||BBh
// | . # # # .     ||
// + - # # # -     ||
// | . # # # .FBBy↑|↓⬍BBy
// | . . . . .    ↓↓
//
// Example Glyph:        Empty rows before bitmap = 9 + -2 - 6 - 0 = 1
//        BBX 5 6 0 0     Empty rows after bitmap = 0 - -2 = 2
//                    Empty columns before bitmap = 0 - 0 = 0
//        BITMAP       Empty columns after bitmap = 6 + 0 - 5 - 0 = 1
// |.....     <= [  0,0,0,0,0, 0] <= 00 (These are the complete rows as hex)
// |.#... 20  <= [],0,0,1,0,0,[0] <= 08 (Any padding bits at the end must be ignored)
// |#.#.. 50  <= [],0,1,0,1,0,[0] <= 14
// #...#. 88  <= [],1,0,0,0,1,[0] <= 22
// #####. f8  <= [],1,1,1,1,1,[0] <= 3e
// #...#. 88  <= [],1,0,0,0,1,[0] <= 22
// #---#- 88  <= [],1,0,0,0,1,[0] <= 22
// |.....     <= [  0,0,0,0,0, 0] <= 00
// |.....     <= [  0,0,0,0,0, 0] <= 00
const Compiler = struct {
    font: *Self,
    glyph: *Glyph,
    bitmap: []u8,
    row: usize = 0, // From the top of the bitmap
    col: usize = 0,
    rows_before: u32 = undefined,
    row_after_glyph: u32 = undefined,
    cols_before: u32 = undefined,
    cols_after: u32 = undefined,

    pub fn new(font: *Self, glyph: *Glyph, buffer: []u8) Compiler {
        const row_after_glyph = @intCast(u32, @as(i32, font.bounds.size.y) + font.bounds.pos.y -
            glyph.bounds.pos.y);
        const r = .{
            .font = font,
            .glyph = glyph,
            .bitmap = glyph.get_bitmap(buffer),
            .rows_before = row_after_glyph - glyph.bounds.size.y,
            .row_after_glyph = row_after_glyph,
            .cols_before = @intCast(u32, @as(i32, glyph.bounds.pos.x) - font.bounds.pos.x),
            .cols_after = @intCast(u32, @as(i32, font.bounds.size.x) + font.bounds.pos.x -
                glyph.bounds.size.x - glyph.bounds.pos.x),
        };
        return r;
    }

    fn compile_pixel(self: *Compiler, value: bool) void {
        const offset = self.glyph.get_byte_offset(self.row, self.col);
        const byte = &self.bitmap[offset];
        set_bit(byte, self.col, value);
        // std.debug.print("{}: {b:0>8}\n", .{offset, byte.*});
        self.col += 1;
    }

    pub fn compile_row(self: *Compiler, line: []const u8) Error!void {
        var col: u16 = undefined;

        // std.debug.print("Above\n", .{});

        // Empty rows above glyph
        while (self.row < self.rows_before) {
            col = 0;
            self.col = 0;
            while (col < self.font.bounds.size.x) {
                self.compile_pixel(false);
                col += 1;
            }
            self.row += 1;
        }

        // std.debug.print("Before\n", .{});

        // Empty columns before glyph row
        col = 0;
        self.col = 0;
        while (col < self.cols_before) {
            self.compile_pixel(false);
            col += 1;
        }

        // std.debug.print("Glyph\n", .{});

        col = 0;
        var left = line;
        while (col < self.glyph.bounds.size.x) {
            const byte = std.fmt.parseUnsigned(u8, left[0..2], 16)
                catch return Error.BdfBadBitmap;
            // std.debug.print("{x}", .{byte});
            var n: u4 = 0;
            while (n < 8 and col < self.glyph.bounds.size.x) {
                self.compile_pixel(get_bit(byte, n));
                n += 1;
                col += 1;
            }
            left = left[2..];
        }

        // std.debug.print("After\n", .{});

        // Empty columns after glyph row
        col = 0;
        while (col < self.cols_after) {
            self.compile_pixel(false);
            col += 1;
        }

        self.row += 1;

        // std.debug.print("Below\n", .{});

        // Empty rows under glyph
        if (self.row >= self.row_after_glyph) {
            while (self.row < self.font.bounds.size.y) {
                col = 0;
                self.col = 0;
                while (col < self.font.bounds.size.x) {
                    self.compile_pixel(false);
                    col += 1;
                }
                self.row += 1;
            }
        }
    }
};

pub const Result = struct {
    need_more_input: bool = false,
    need_buffer: ?usize = null,
    glyph: ?Glyph = null,
    done: bool = false,

    pub fn verify(self: *const Result) void {
        if (!(self.need_more_input or self.need_buffer != null or
                self.glyph != null or self.done)) {
            @panic("Bdf.Result is invalid");
        }
    }
};

pub const Parser = struct {
    const StateKind = enum {
        BeforeStartFont,
        AfterStartFont,
        Properties,
        Glyphs,
        Glyph,
        GlyphBitmap,
        EndFont,
    };

    const State = union(StateKind) {
        BeforeStartFont: void,
        AfterStartFont: void,
        Properties: struct {
            expected: u16,
            got: u16 = 0,
        },
        Glyphs: void,
        Glyph: void,
        GlyphBitmap: struct {
            expected_lines: u16,
            expected_line_len: u16,
            compiler: Compiler,
        },
        EndFont: void,
    };

    const Keyword = enum {
        StartFont,
        Comment,
        FontBoundingBox,
        StartProperties,
        Chars,
        StartChar,
        Encoding,
        Bbx,
        Bitmap,
        EndFont,
        Unknown,

        pub fn from_string(string: []const u8) Keyword {
            if (streq(string, "STARTFONT")) {
                return .StartFont;
            } else if (streq(string, "COMMENT")) {
                return .Comment;
            } else if (streq(string, "FONTBOUNDINGBOX")) {
                return .FontBoundingBox;
            } else if (streq(string, "STARTPROPERTIES")) {
                return .StartProperties;
            } else if (streq(string, "CHARS")) {
                return .Chars;
            } else if (streq(string, "STARTCHAR")) {
                return .StartChar;
            } else if (streq(string, "ENCODING")) {
                return .Encoding;
            } else if (streq(string, "BBX")) {
                return .Bbx;
            } else if (streq(string, "BITMAP")) {
                return .Bitmap;
            } else if (streq(string, "ENDFONT")) {
                return .EndFont;
            } else {
                return .Unknown;
            }
        }
    };

    const max_line_len: usize = 256;
    const more_input = Result{.need_more_input = true};

    line_buffer: [max_line_len]u8 = [_]u8{0} ** max_line_len,
    word_it_buffer: [max_line_len]u8 = undefined,
    line_pos: usize = 0,
    line_no: usize = 0,
    last_result: Result = more_input,
    glyphs_got: u32 = 0,
    font: Self = .{},
    current_glyph: Glyph = undefined,
    state: State = State{.BeforeStartFont = void{}},
    buffer: ?[]u8 = null,

    fn parse_int_value(it: *WordIterator, comptime Int: type, base: comptime_int) Error!Int {
        const str = (try it.next()) orelse return Error.BdfMissingValue;
        return std.fmt.parseInt(Int, str, base) catch return Error.BdfBadValue;
    }

    fn parse_point_i(it: *WordIterator, comptime PointType: type, point: *PointType) Error!void {
        for ([_]*PointType.Num{&point.x, &point.y}) |num| {
            num.* = try parse_int_value(it, PointType.Num, 10);
        }
    }

    fn parse_box_i(it: *WordIterator, comptime BoxType: type, box: *BoxType) Error!void {
        try parse_point_i(it, BoxType.Size, &box.size);
        try parse_point_i(it, BoxType.Pos, &box.pos);
    }

    fn parse_bounds(it: *WordIterator, bounds: *Bounds) Error!void {
        try parse_box_i(it, Bounds, bounds);
    }

    fn process_line(self: *Parser, line: []const u8) Error!Result {
        self.line_no += 1;
        // std.debug.print("LINE: {} {s}\n", .{self.line_no, line});
        var it = WordIterator{
            .quote = '\"', .input = line,
            .buffer = self.word_it_buffer[0..],
        };
        switch (self.state) {
            StateKind.BeforeStartFont => {
                const kw = (try it.next()) orelse return more_input;
                // std.debug.print("BeforeStartFont keyword: {s}\n", .{kw});
                if (Keyword.from_string(kw) == .StartFont) {
                    self.state = State{.AfterStartFont = void{}};
                } else {
                    return Error.BdfBadKeyword;
                }
            },

            StateKind.AfterStartFont => {
                const kw = (try it.next()) orelse return more_input;
                // std.debug.print("AfterStartFont keyword: {s}\n", .{kw});
                switch (Keyword.from_string(kw)) {
                    .Comment, .Unknown => {},
                    .FontBoundingBox => {
                        try parse_bounds(&it, &self.font.bounds);
                    },
                    .StartProperties => self.state = State{.Properties = .{.expected =
                        try parse_int_value(&it, u16, 10)}},
                    .Chars => {
                        self.font.glyph_count = try parse_int_value(&it, u32, 10);
                        self.state = State{.Glyphs = .{}};
                        return Result{.need_buffer = self.font.required_buffer_size()};
                    },
                    else => return Error.BdfBadKeyword,
                }
            },

            StateKind.Properties => |*state_info| {
                const kw = (try it.next()) orelse return more_input;
                if (streq(kw, "COMMENT")) {
                    return more_input;
                } else if (streq(kw, "ENDPROPERTIES")) {
                    if (state_info.expected < state_info.got) {
                        return Error.BdfBadPropCount;
                    }
                    self.state = State{.AfterStartFont = void{}};
                } else {
                    if (state_info.expected == state_info.got) {
                        return Error.BdfBadPropCount;
                    }
                    state_info.got += 1;
                    if (streq(kw, "FONT_NAME")) {
                        const name = (try it.next()) orelse return Error.BdfMissingValue;
                        self.font.name.ts().string_truncate(name);
                    } else if (streq(kw, "DEFAULT_CHAR")) {
                        self.font.default_codepoint = try parse_int_value(&it, u32, 10);
                    }
                }
            },

            StateKind.Glyphs => {
                const kw = (try it.next()) orelse return more_input;
                // std.debug.print("Glyphs keyword: {s}\n", .{kw});
                switch (Keyword.from_string(kw)) {
                    .Comment => {},
                    .StartChar => {
                        if (self.glyphs_got == self.font.glyph_count) {
                            return Error.BdfBadGlyphCount;
                        }
                        self.current_glyph = Glyph.new(&self.font, self.glyphs_got);
                        self.glyphs_got += 1;
                        // TODO Glyph name from arg
                        self.state = State{.Glyph = void{}};
                    },
                    .EndFont => {
                        if (self.glyphs_got < self.font.glyph_count) {
                            return Error.BdfBadGlyphCount;
                        }
                        if (!self.font.found_default_codepoint) {
                            return Error.BdfMissingDefaultCodepoint;
                        }
                        self.state = State{.EndFont = void{}};
                        return Result{.done = true};
                    },
                    else => return Error.BdfBadKeyword,
                }
            },

            StateKind.Glyph => {
                const kw = (try it.next()) orelse return more_input;
                // std.debug.print("Glyph keyword: {s}\n", .{kw});
                switch (Keyword.from_string(kw)) {
                    .Comment, .Unknown => {},
                    // TODO Test the following are being set
                    .Encoding => {
                        self.current_glyph.codepoint = try parse_int_value(&it, u32, 10);
                        if (self.current_glyph.codepoint == self.font.default_codepoint) {
                            self.font.found_default_codepoint = true;
                        }
                    },
                    .Bbx => {
                        try parse_bounds(&it, &self.current_glyph.bounds);
                    },
                    .Bitmap => {
                        // TODO: Check for BBX and put results into state
                        self.state = State{.GlyphBitmap = .{
                            .expected_lines = 0,
                            .expected_line_len = 0,
                            .compiler = Compiler.new(&self.font, &self.current_glyph, self.buffer.?),
                        }};
                    },
                    else => return Error.BdfBadKeyword,
                }
            },

            StateKind.GlyphBitmap => |*state_info| {
                _ = state_info; // TODO
                if (line.len == 0) return more_input;
                // std.debug.print("Bitmap Line: \"{s}\"\n", .{line});
                if (streq(line, "ENDCHAR"))  {
                    // TODO: Check we got enough lines
                    self.state = State{.Glyphs = .{}};
                    return Result{.glyph = self.current_glyph, .need_more_input = true};
                } else {
                    // TODO: Check this isn't too many lines
                    // TODO: Check line length matches expected
                    try state_info.compiler.compile_row(line);
                }
            },

            StateKind.EndFont => return Result{.done = true},
        }
        return more_input;
    }

    pub fn feed_input(self: *Parser, chunk: []const u8, chunk_pos: *usize) Error!Result {
        if (self.last_result.glyph != null) {
            self.last_result.glyph = null;
        }

        if (self.last_result.need_buffer != null) {
            if (self.buffer == null) {
                return Error.BdfMissingBuffer;
            }
            if (self.buffer.?.len < self.font.required_buffer_size()) {
                return Error.BdfBufferTooSmall;
            }
            for (self.buffer.?) |*byte| {
                byte.* = 0;
            }
            self.last_result.need_buffer = null;
        }

        if (chunk_pos.* >= chunk.len) {
            return more_input;
        }

        var process_chunk = true;
        var chunk_done: bool = undefined;
        while (process_chunk) {
            const c = chunk[chunk_pos.*];
            var newline = c == '\n';
            if (newline) {
                self.last_result = try self.process_line(self.line_buffer[0..self.line_pos]);
                self.line_pos = 0;
            } else {
                self.line_buffer[self.line_pos] = c;
                self.line_pos += 1;
            }
            chunk_pos.* += 1;
            chunk_done = chunk_pos.* >= chunk.len;

            // Done, nothing else to do, exit loop
            if (self.last_result.done) {
                process_chunk = false;
            // Not done, chunk done, need more from user, may also ask for
            // buffer or have glyph, so exit loop.
            } else if (chunk_done) {
                self.last_result.need_more_input = true;
                process_chunk = false;
            // Not done, chunk not empty, but needs buffer or has glyph, so
            // exit loop
            } else if (self.last_result.need_buffer != null or self.last_result.glyph != null) {
                // Still working on current chunk
                self.last_result.need_more_input = false;
                process_chunk = false;
            }
            // Else it isn't done with the chunk yet or doesn't need the buffer
        }

        self.last_result.verify();

        return self.last_result;
    }
};

fn test_parse_font(allocator: *const std.mem.Allocator, parser: *Parser,
        bdf_text: []const u8, max_chunk_len: usize) !void {
    const start_chunk_size = @minimum(bdf_text.len, max_chunk_len);
    var chunk: []const u8 = bdf_text[0..start_chunk_size];
    var chunk_pos: usize = 0;
    var left: []const u8 = bdf_text[start_chunk_size..];
    while (true) {
        const result = try parser.feed_input(chunk, &chunk_pos);
        if (result.done) break;

        if (result.glyph) |glyph| {
            _ = glyph;
        }

        if (result.need_more_input) {
            const chunk_size = @minimum(left.len, max_chunk_len);
            chunk = left[0..chunk_size];
            left = left[chunk_size..];
            chunk_pos = 0;
        }

        if (result.need_buffer) |buffer_size| {
            parser.buffer = try allocator.alloc(u8, buffer_size);
        }
    }
}

test "Bdf" {
    const bdf_text =
        \\STARTFONT
        \\COMMENT This is a test comment
        \\FONTBOUNDINGBOX 6 9 0 -2
        \\STARTPROPERTIES 2
        \\FONT_NAME "The Font Name"
        \\DEFAULT_CHAR 65
        \\ENDPROPERTIES
        \\CHARS 1
        \\STARTCHAR A
        \\ENCODING 65
        \\BBX 5 6 0 0
        \\BITMAP
        \\20
        \\50
        \\88
        \\f8
        \\88
        \\88
        \\ENDCHAR
        \\ENDFONT
        \\
        ;

    var parser = Parser{};
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    // 3 because we need to be sure the input can be constrained
    try test_parse_font(&allocator, &parser, bdf_text, 3);

    try std.testing.expectEqualStrings(parser.font.name.ts().get(), "The Font Name");
    try std.testing.expectEqual(parser.font.glyph_count, 1);
    try std.testing.expectEqual(parser.font.bounds.size.x, 6);
    try std.testing.expectEqual(parser.font.bounds.size.y, 9);
    try std.testing.expectEqual(parser.font.bounds.pos.x, 0);
    try std.testing.expectEqual(parser.font.bounds.pos.y, -2);
    try std.testing.expectEqual(parser.font.default_codepoint, 'A');
    try std.testing.expectEqual(parser.current_glyph.codepoint, 65);
    try std.testing.expectEqual(parser.current_glyph.bounds.size.x, 5);
    try std.testing.expectEqual(parser.current_glyph.bounds.size.y, 6);
    try std.testing.expectEqual(parser.current_glyph.bounds.pos.x, 0);
    try std.testing.expectEqual(parser.current_glyph.bounds.pos.y, 0);

    // Test that the Compiler is putting the right bytes in the buffer
    {
        const expected = [_]u8{
            0x00,
            0x20,
            0x50,
            0x88,
            0xf8,
            0x88,
            0x88,
            0x00,
            0x00,
        };
        try std.testing.expectEqualSlices(u8, expected[0..], parser.buffer.?);
    }

    // Test Glyph.Iterator indirectly
    {
        const expected =
            "......\n" ++
            "..#...\n" ++
            ".#.#..\n" ++
            "#...#.\n" ++
            "#####.\n" ++
            "#...#.\n" ++
            "#...#.\n" ++
            "......\n" ++
            "......\n";
        var buffer = [_]u8{0} ** 63;
        try std.testing.expectEqualStrings(expected[0..],
            try parser.current_glyph.preview(parser.buffer.?, buffer[0..]));
    }
}

test "Bdf parse builtin_font.bdf" {
    const bdf_text = @embedFile("../../kernel/builtin_font.bdf");
    var parser = Parser{};
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    try test_parse_font(&allocator, &parser, bdf_text, 128);
}
