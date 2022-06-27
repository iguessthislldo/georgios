// Parser and renderer for Bitmap Distribution Format (BDF) monospace fonts.
// It skips a good chunk of BDF spec details because they don't matter for
// monospace fonts or at least didn't seem to matter for the monospace fonts
// I've seen so far.
//
// For reference:
//   https://en.wikipedia.org/wiki/Glyph_Bitmap_Distribution_Format
//   https://adobe-type-tools.github.io/font-tech-notes/pdfs/5005.BDF_Spec.pdf

const Self = @This();

const std = @import("std");

const utils = @import("utils.zig");
const WordIterator = utils.WordIterator;
const Point = utils.Point;
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
} || utils.Error;

pub const filled_pixel: u32 = 0xffffffff;
pub const empty_pixel: u32 = 0x00000000;

pub const Font = struct {
    name: utils.FixedString(64) = .{}, // FONT_NAME Property
    bounds: Bounds = .{}, // FONTBOUNDINGBOX
    glyph_count: u32 = 0, // CHARS

    pub fn glyph_size(self: *const Font) usize {
        return @as(usize, self.bounds.size.x) * self.bounds.size.y;
    }

    pub fn required_buffer_size(self: *const Font) usize {
        return @as(usize, self.glyph_count) * self.glyph_size();
    }
};

pub const Glyph = struct {
    bitmap: []u32, // BITMAP
    name: ?[]const u8 = null, // STARTFONT
    codepoint: ?u32 = null, // ENCODING
    bounds: Bounds = .{}, // BBX

    pub fn preview(self: *const Glyph, font: *const Font) void {
        var offset: usize = 0;
        var row: usize = 0;
        while (row < font.bounds.size.y) {
            var col: usize = 0;
            while (col < font.bounds.size.x) {
                var char: u8 = '?';
                if (self.bitmap[offset] == filled_pixel) {
                    char = '#';
                } else if (self.bitmap[offset] == empty_pixel) {
                    char = '.';
                }
                std.debug.print("{c}", .{char});
                col += 1;
                offset += 1;
            }
            std.debug.print("\n", .{});
            row += 1;
        }
    }
};

pub const ResultKind = enum {
    NeedMoreInput,
    NeedBufferAndMoreInput,
    Done,
};

pub const Result = union(ResultKind) {
    NeedMoreInput: void,
    NeedBufferAndMoreInput: usize,
    Done: void,
};

// Thinking out rendering:
//
// An example font is 6x9 pixels and can extend two pixels below the baseline.
// In BDF, this means the "FONTBOUNDINGBOX" is "6 9 0 -2". All glyphs should be
// able to fit in this box:
//
// |..... "+" is origin and the horizontal line is the baseline.
// |.....
// |..... All fonts should be able to be prerendered into a bitmap image
// |..... from the font bitmap data and then copied into video memory.
// |.....
// |..... BDF bitmap data doesn't have to fill out the entire font bounding
// +----- box. Rendering will have to position the glyph correctly.
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
// |.....     <= [  0,0,0,0,0, 0]
// |.#... 20  <= [],0,0,1,0,0,[0]
// |#.#.. 50  <= [],0,1,0,1,0,[0]
// #...#. 88  <= [],1,0,0,0,1,[0]
// #####. f8  <= [],1,1,1,1,1,[0]
// #...#. 88  <= [],1,0,0,0,1,[0]
// #---#- 88  <= [],1,0,0,0,1,[0]
// |.....     <= [  0,0,0,0,0, 0]
// |.....     <= [  0,0,0,0,0, 0]
const Renderer = struct {
    font: *Font,
    glyph: *Glyph,
    offset: usize = 0,
    row: usize = 0, // From the top of the bitmap
    rows_before: u32 = undefined,
    row_after_glyph: u32 = undefined,
    cols_before: u32 = undefined,
    cols_after: u32 = undefined,

    pub fn new(font: *Font, glyph: *Glyph) Renderer {
        const row_after_glyph = @intCast(u32, @as(i32, font.bounds.size.y) + font.bounds.pos.y -
            glyph.bounds.pos.y);
        return .{
            .font = font,
            .glyph = glyph,
            .rows_before = row_after_glyph - glyph.bounds.size.y,
            .row_after_glyph = row_after_glyph,
            .cols_before = @intCast(u32, @as(i32, glyph.bounds.pos.x) - font.bounds.pos.x),
            .cols_after = @intCast(u32, @as(i32, font.bounds.size.x) + font.bounds.pos.x -
                glyph.bounds.size.x - glyph.bounds.pos.x),
        };
    }

    fn render_pixel(self: *Renderer, value: bool) void {
        const bitmap_value = @as(u32, if (value) filled_pixel else empty_pixel);
        self.glyph.bitmap[self.offset] = bitmap_value;
        self.offset += 1;
    }

    pub fn render_row(self: *Renderer, line: []const u8) Error!void {
        var col: u16 = undefined;

        // Empty rows above glyph
        while (self.row < self.rows_before) {
            col = 0;
            while (col < self.font.bounds.size.x) {
                self.render_pixel(false);
                col += 1;
            }
            self.row += 1;
        }

        // Empty columns before glyph row
        col = 0;
        while (col < self.cols_before) {
            self.render_pixel(false);
            col += 1;
        }

        col = 0;
        var left = line;
        while (col < self.glyph.bounds.size.x) {
            const byte = std.fmt.parseUnsigned(u8, left[0..2], 16)
                catch return Error.BdfBadBitmap;
            // std.debug.print("{x}", .{byte});
            var n: u4 = 0;
            while (n < 8 and col < self.glyph.bounds.size.x) {
                self.render_pixel((byte >> (7 - @intCast(u3, n))) & 1 == 1);
                n += 1;
                col += 1;
            }
            left = left[2..];
        }

        // Empty columns after glyph row
        col = 0;
        while (col < self.cols_after) {
            self.render_pixel(false);
            col += 1;
        }

        self.row += 1;

        // Empty rows under glyph
        if (self.row >= self.row_after_glyph) {
            while (self.row < self.font.bounds.size.y) {
                col = 0;
                while (col < self.font.bounds.size.x) {
                    self.render_pixel(false);
                    col += 1;
                }
                self.row += 1;
            }
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
            renderer: Renderer,
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
    const more_input = Result{.NeedMoreInput = void{}};

    line_buffer: [max_line_len]u8 = [_]u8{0} ** max_line_len,
    word_it_buffer: [max_line_len]u8 = undefined,
    line_pos: usize = 0,
    line_no: usize = 0,
    last_result: Result = more_input,
    glyphs_got: u32 = 0,
    font: Font = .{},
    current_glyph: Glyph = undefined,
    state: State = State{.BeforeStartFont = void{}},
    buffer: ?[]u32= null,

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
                if (Keyword.from_string(kw) == .StartFont) {
                    self.state = State{.AfterStartFont = void{}};
                } else {
                    return Error.BdfBadKeyword;
                }
            },

            StateKind.AfterStartFont => {
                const kw = (try it.next()) orelse return more_input;
                std.debug.print("AfterStartFont keyword: {s}\n", .{kw});
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
                        return Result{.NeedBufferAndMoreInput = self.font.required_buffer_size()};
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
                    }
                }
            },

            StateKind.Glyphs => {
                const kw = (try it.next()) orelse return more_input;
                std.debug.print("Glyphs keyword: {s}\n", .{kw});
                switch (Keyword.from_string(kw)) {
                    .Comment => {},
                    .StartChar => {
                        if (self.glyphs_got == self.font.glyph_count) {
                            return Error.BdfBadGlyphCount;
                        }
                        const start = self.glyphs_got * self.font.glyph_size();
                        const end = start + self.font.glyph_size();
                        self.current_glyph = .{.bitmap = self.buffer.?[start..end]};
                        self.glyphs_got += 1;
                        // TODO Glyph name from arg
                        self.state = State{.Glyph = void{}};
                    },
                    .EndFont => {
                        if (self.glyphs_got < self.font.glyph_count) {
                            return Error.BdfBadGlyphCount;
                        }
                        self.state = State{.EndFont = void{}};
                        return .Done;
                    },
                    else => return Error.BdfBadKeyword,
                }
            },

            StateKind.Glyph => {
                const kw = (try it.next()) orelse return more_input;
                std.debug.print("Glyph keyword: {s}\n", .{kw});
                switch (Keyword.from_string(kw)) {
                    .Comment, .Unknown => {},
                    // TODO Test the following are being set
                    .Encoding => {
                        self.current_glyph.codepoint = try parse_int_value(&it, u32, 10);
                    },
                    .Bbx => {
                        try parse_bounds(&it, &self.current_glyph.bounds);
                    },
                    .Bitmap => {
                        // TODO: Check for BBX and put results into state
                        self.state = State{.GlyphBitmap = .{
                            .expected_lines = 0,
                            .expected_line_len = 0,
                            .renderer = Renderer.new(&self.font, &self.current_glyph),
                        }};
                    },
                    else => return Error.BdfBadKeyword,
                }
            },

            StateKind.GlyphBitmap => |*state_info| {
                _ = state_info; // TODO
                if (line.len == 0) return more_input;
                if (streq(line, "ENDCHAR"))  {
                    self.current_glyph.preview(&self.font);
                    // TODO: Check we got enough lines
                    self.state = State{.Glyphs = .{}};
                } else {
                    // TODO: Check this isn't too many lines
                    // TODO: Check line length matches expected
                    try state_info.renderer.render_row(line);
                }
            },

            StateKind.EndFont => return .Done,
        }
        return more_input;
    }

    pub fn feed_input(self: *Parser, chunk: []const u8) Error!Result {
        while (true) {
            switch (self.last_result) {
                .NeedMoreInput => {
                    for (chunk) |c| {
                        if (c == '\n') {
                            self.last_result = try self.process_line(
                                self.line_buffer[0..self.line_pos]);
                            self.line_pos = 0;
                        } else {
                            self.line_buffer[self.line_pos] = c;
                            self.line_pos += 1;
                        }
                    }
                    return self.last_result;
                },
                .NeedBufferAndMoreInput => {
                    if (self.buffer == null) {
                        return Error.BdfMissingBuffer;
                    }
                    if (self.buffer.?.len < self.font.required_buffer_size()) {
                        return Error.BdfBufferTooSmall;
                    }
                    self.last_result = more_input;
                },
                .Done => return self.last_result,
            }
        }
    }
};

test "Bdf" {
    const test_font =
        \\STARTFONT
        \\COMMENT This is a test comment
        \\FONTBOUNDINGBOX 6 9 0 -2
        \\STARTPROPERTIES 1
        \\FONT_NAME "The Font Name"
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
    var left: []const u8 = test_font[0..];
    var buffer: [54]u32 = undefined;
    while (true) {
        const chunk_size = @minimum(left.len, 3);
        // 3 because we need to be sure the input can be constrained
        const chunk: []const u8 = left[0..chunk_size];
        left = left[chunk_size..];
        switch (try parser.feed_input(chunk)) {
            .NeedMoreInput => {},
            .NeedBufferAndMoreInput => |buffer_size| {
                std.debug.print("NEED BUFFER: {}\n", .{buffer_size});
                parser.buffer = buffer[0..];
            },
            .Done => break,
        }
    }

    try std.testing.expectEqualStrings(parser.font.name.ts().get(), "The Font Name");
    try std.testing.expectEqual(parser.font.glyph_count, 1);
    try std.testing.expectEqual(parser.font.bounds.size.x, 6);
    try std.testing.expectEqual(parser.font.bounds.size.y, 9);
    try std.testing.expectEqual(parser.font.bounds.pos.x, 0);
    try std.testing.expectEqual(parser.font.bounds.pos.y, -2);
    try std.testing.expectEqual(parser.current_glyph.codepoint, 65);
    try std.testing.expectEqual(parser.current_glyph.bounds.size.x, 5);
    try std.testing.expectEqual(parser.current_glyph.bounds.size.y, 6);
    try std.testing.expectEqual(parser.current_glyph.bounds.pos.x, 0);
    try std.testing.expectEqual(parser.current_glyph.bounds.pos.y, 0);

    const B = filled_pixel;
    const j = empty_pixel;
    const expected = [_]u32{
        j, j, j, j, j, j,
        j, j, B, j, j, j,
        j, B, j, B, j, j,
        B, j, j, j, B, j,
        B, B, B, B, B, j,
        B, j, j, j, B, j,
        B, j, j, j, B, j,
        j, j, j, j, j, j,
        j, j, j, j, j, j,
    };
    try std.testing.expectEqualSlices(u32, parser.buffer.?, expected[0..]);
}
