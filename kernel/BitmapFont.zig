const Self = @This();

const std = @import("std");

const utils = @import("utils");
const Bdf = utils.Bdf;
const Glyph = Bdf.Glyph;

const kernel = @import("kernel.zig");
const Allocator = kernel.memory.Allocator;

pub const Codepoint = u32;
pub const GlyphIndex = struct {
    codepoint: Codepoint,
    index: usize,
};
const GlyphIndexMap = std.AutoArrayHashMap(Codepoint, usize);

bdf_font: *const Bdf,
glyph_index_map: GlyphIndexMap,
raw_bitmaps: []const u8,

pub fn init(self: *Self, bdf_font: *const Bdf,
        glyph_indices: []const GlyphIndex, raw_bitmaps: []const u8) !void {
    self.* = .{
        .bdf_font = bdf_font,
        .glyph_index_map = GlyphIndexMap.init(kernel.alloc.std_allocator()),
        .raw_bitmaps = raw_bitmaps,
    };
    for (glyph_indices) |glyph_index| {
        try self.glyph_index_map.put(glyph_index.codepoint, glyph_index.index);
    }
}

const GlyphHolder = struct {
    glyph: Glyph,
    raw_bitmaps: []const u8,

    pub fn iter_pixels(self: *const GlyphHolder) Glyph.Iterator {
        return self.glyph.iter_pixels(self.raw_bitmaps);
    }
};

pub fn get(self: *const Self, codepoint: Codepoint) GlyphHolder {
    var index: usize = 0;
    if (self.glyph_index_map.get(codepoint)) |cp_index| {
        index = cp_index;
    } else {
        index = self.glyph_index_map.get(self.bdf_font.default_codepoint).?;
    }
    return .{.glyph = Glyph.new(self.bdf_font, index), .raw_bitmaps = self.raw_bitmaps};
}

pub fn done(self: *Self) void {
    self.glyph_bitmap_offset_map.deinit();
}
