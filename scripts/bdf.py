#!/usr/bin/env python3

import sys

class Glyph:
    def __init__(self, codepoint):
        self.codepoint = codepoint
        self.bitmap = []

    def bbx(self, w, h, x, y):
        self.w = w
        self.h = h
        self.x = x
        self.y = y

    def __repr__(self):
        return hex(self.codepoint)

class Parser:

    def __init__(self):
        self.bitmap_rows = None
        self.glyph = None
        self.glyphs = []

    def parse_line(self, line, lineno):
        if self.bitmap_rows is not None:
            self.bitmap_rows -= 1
            # for c in line:
            #     x = int(c, 16)
            #     print('#' if x & 8 else ' ', end='')
            #     print('#' if x & 4 else ' ', end='')
            #     print('#' if x & 2 else ' ', end='')
            #     print('#' if x & 1 else ' ', end='')
            # print('')
            ll = len(line)
            self.glyph.bitmap.append([int(line[i:i + 2], 16) for i in range(0, ll, 2)])
            if self.bitmap_rows == 0:
                self.bitmap_rows = None
            return

        keyword, _, args = line.partition(' ')

        if keyword == 'STARTCHAR':
            if self.glyph is not None:
                sys.exit('Error on ' + str(lineno))

            codepoint = int(args[2:], 16)
            if 0x20 <= codepoint <= 0x7e:
                # print(hex(codepoint))
                self.glyph = Glyph(codepoint)

        elif keyword == 'BBX' and self.glyph:
            self.glyph.bbx(*[int(i) for i in args.split(' ')])

        elif keyword == 'BITMAP' and self.glyph:
            self.bitmap_rows = self.glyph.h

        elif keyword == 'ENDCHAR' and self.glyph:
            self.glyphs.append(self.glyph)
            self.glyph = None

    def parse(self, it):
        for line_index, line in enumerate(it):
            line = line.rstrip()
            self.parse_line(line, line_index + 1)

parser = Parser()
parser.parse(sys.stdin)
glyphs = parser.glyphs
glyphs.sort(key=lambda i: i.codepoint)

width = glyphs[0].w
height = glyphs[0].h
for glyph in glyphs[1:]:
    if glyph.w != width:
        sys.exit('Inconsistent Width: ' + repr(glyph))
    if glyph.h != height:
        sys.exit('Inconsistent Height')
print('pub const width: usize = {};'.format(width))
print('pub const height: usize = {};'.format(height))
print('')
row_byte_size = ((width + 7) & ~7) // 8

print('pub const bitmaps = [{}][{}][{}]u8 {{'.format(len(glyphs), height, row_byte_size))
for glyph in glyphs:
    print('    [{}][{}]u8{{'.format(height, row_byte_size))
    for row in glyph.bitmap:
        print('        [_]u8{{{}}},'.format(', '.join([hex(b) for b in row])))
    print('    },')
print('};')
