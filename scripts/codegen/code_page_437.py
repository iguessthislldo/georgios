# Generate conversion code from Unicode Code Point to Code Page 437, the IBM PC
# CGA builtin character set.

import sys

zig_file = 'kernel/platform/code_point_437.zig'

# Utilities ==================================================================
class KeyValue:
    def __init__(self, key, value):
        self.key = key
        self.value = value

    def __lt__(self, other):
        return self.key < other.key

    def __repr__(self):
        return '<0x{:04x}: 0x{:02x}>'.format(self.key, self.value)

    def offset(self):
        return self.key - self.value

class Range:
    def __init__(self, kv=None):
        self.kvs = [kv] if kv is not None else []

    def goes_next(self, keyvalue):
        if keyvalue is None or (self.kvs and keyvalue.key != self.kvs[-1].key + 1):
            return False
        self.kvs.append(keyvalue)
        return True

    def same_offset(self):
        if self.kvs:
            first_offset = self.kvs[0].offset()
            for kv in self.kvs[1:]:
                if kv.offset() != first_offset:
                    return None
            return first_offset
        return None

    def __len__(self):
        return len(self.kvs)

    def __bool_(self):
        return len(self.kvs) > 0

    def __repr__(self):
        if self.kvs:
            return '<{} -> {} ({})>'.format(
                repr(self.kvs[0]), repr(self.kvs[-1]), len(self.kvs))
        else:
            return '<(0)>'

def get_ranges(l):
    ranges = [Range(l[0])]
    for kv in l[1:]:
        if not ranges[-1].goes_next(kv):
            ranges.append(Range(kv))
    return ranges

# Code Page 437 Unicode Data =================================================
# Based on the table in https://en.wikipedia.org/wiki/Code_page_437
keys = [
    # 0/NUL is left to an unknown, because it would be the same as a space in
    # 437, but I don't think it should.
    None,
    0x263a, # "☺" WHITE SMILING FACE
    0x263b, # "☻" BLACK SMILING FACE
    0x2665, # "♥" BLACK HEART SUIT
    0x2666, # "♦" BLACK DIAMOND SUIT
    0x2663, # "♣" BLACK CLUB SUIT
    0x2660, # "♠" BLACK SPADE SUIT
    0x2022, # "•" BULLET
    0x25d8, # "◘" INVERSE BULLET
    0x25cb, # "○" WHITE CIRCLE
    0x25d9, # "◙" INVERSE WHITE CIRCLE
    0x2642, # "♂" MALE SIGN
    0x2640, # "♀" FEMALE SIGN
    0x266a, # "♪" EIGHTH NOTE
    0x266b, # "♫" BEAMED EIGHTH NOTES
    0x263c, # "☼" WHITE SUN WITH RAYS
    0x25ba, # "►" BLACK RIGHT-POINTING POINTER
    0x25c4, # "◄" BLACK LEFT-POINTING POINTER
    0x2195, # "↕" UP DOWN ARROW
    0x203c, # "‼" DOUBLE EXCLAMATION MARK
    0x00b6, # "¶" PILCROW SIGN
    0x00a7, # "§" SECTION SIGN
    0x25ac, # "▬" BLACK RECTANGLE
    0x21a8, # "↨" UP DOWN ARROW WITH BASE
    0x2191, # "↑" UPWARDS ARROW
    0x2193, # "↓" DOWNWARDS ARROW
    0x2192, # "→" RIGHTWARDS ARROW
    0x2190, # "←" LEFTWARDS ARROW
    0x221f, # "∟" RIGHT ANGLE
    0x2194, # "↔" LEFT RIGHT ARROW
    0x25b2, # "▲" BLACK UP-POINTING TRIANGLE
    0x25bc, # "▼" BLACK DOWN-POINTING TRIANGLE
    0x0020, # " " SPACE
    0x0021, # "!" EXCLAMATION MARK
    0x0022, # """ QUOTATION MARK
    0x0023, # "#" NUMBER SIGN
    0x0024, # "$" DOLLAR SIGN
    0x0025, # "%" PERCENT SIGN
    0x0026, # "&" AMPERSAND
    0x0027, # "'" APOSTROPHE
    0x0028, # "(" LEFT PARENTHESIS
    0x0029, # ")" RIGHT PARENTHESIS
    0x002a, # "*" ASTERISK
    0x002b, # "+" PLUS SIGN
    0x002c, # "," COMMA
    0x002d, # "-" HYPHEN-MINUS
    0x002e, # "." FULL STOP
    0x002f, # "/" SOLIDUS
    0x0030, # "0" DIGIT ZERO
    0x0031, # "1" DIGIT ONE
    0x0032, # "2" DIGIT TWO
    0x0033, # "3" DIGIT THREE
    0x0034, # "4" DIGIT FOUR
    0x0035, # "5" DIGIT FIVE
    0x0036, # "6" DIGIT SIX
    0x0037, # "7" DIGIT SEVEN
    0x0038, # "8" DIGIT EIGHT
    0x0039, # "9" DIGIT NINE
    0x003a, # ":" COLON
    0x003b, # ";" SEMICOLON
    0x003c, # "<" LESS-THAN SIGN
    0x003d, # "=" EQUALS SIGN
    0x003e, # ">" GREATER-THAN SIGN
    0x003f, # "?" QUESTION MARK
    0x0040, # "@" COMMERCIAL AT
    0x0041, # "A" LATIN CAPITAL LETTER A
    0x0042, # "B" LATIN CAPITAL LETTER B
    0x0043, # "C" LATIN CAPITAL LETTER C
    0x0044, # "D" LATIN CAPITAL LETTER D
    0x0045, # "E" LATIN CAPITAL LETTER E
    0x0046, # "F" LATIN CAPITAL LETTER F
    0x0047, # "G" LATIN CAPITAL LETTER G
    0x0048, # "H" LATIN CAPITAL LETTER H
    0x0049, # "I" LATIN CAPITAL LETTER I
    0x004a, # "J" LATIN CAPITAL LETTER J
    0x004b, # "K" LATIN CAPITAL LETTER K
    0x004c, # "L" LATIN CAPITAL LETTER L
    0x004d, # "M" LATIN CAPITAL LETTER M
    0x004e, # "N" LATIN CAPITAL LETTER N
    0x004f, # "O" LATIN CAPITAL LETTER O
    0x0050, # "P" LATIN CAPITAL LETTER P
    0x0051, # "Q" LATIN CAPITAL LETTER Q
    0x0052, # "R" LATIN CAPITAL LETTER R
    0x0053, # "S" LATIN CAPITAL LETTER S
    0x0054, # "T" LATIN CAPITAL LETTER T
    0x0055, # "U" LATIN CAPITAL LETTER U
    0x0056, # "V" LATIN CAPITAL LETTER V
    0x0057, # "W" LATIN CAPITAL LETTER W
    0x0058, # "X" LATIN CAPITAL LETTER X
    0x0059, # "Y" LATIN CAPITAL LETTER Y
    0x005a, # "Z" LATIN CAPITAL LETTER Z
    0x005b, # "[" LEFT SQUARE BRACKET
    0x005c, # "\" REVERSE SOLIDUS
    0x005d, # "]" RIGHT SQUARE BRACKET
    0x005e, # "^" CIRCUMFLEX ACCENT
    0x005f, # "_" LOW LINE
    0x0060, # "`" GRAVE ACCENT
    0x0061, # "a" LATIN SMALL LETTER A
    0x0062, # "b" LATIN SMALL LETTER B
    0x0063, # "c" LATIN SMALL LETTER C
    0x0064, # "d" LATIN SMALL LETTER D
    0x0065, # "e" LATIN SMALL LETTER E
    0x0066, # "f" LATIN SMALL LETTER F
    0x0067, # "g" LATIN SMALL LETTER G
    0x0068, # "h" LATIN SMALL LETTER H
    0x0069, # "i" LATIN SMALL LETTER I
    0x006a, # "j" LATIN SMALL LETTER J
    0x006b, # "k" LATIN SMALL LETTER K
    0x006c, # "l" LATIN SMALL LETTER L
    0x006d, # "m" LATIN SMALL LETTER M
    0x006e, # "n" LATIN SMALL LETTER N
    0x006f, # "o" LATIN SMALL LETTER O
    0x0070, # "p" LATIN SMALL LETTER P
    0x0071, # "q" LATIN SMALL LETTER Q
    0x0072, # "r" LATIN SMALL LETTER R
    0x0073, # "s" LATIN SMALL LETTER S
    0x0074, # "t" LATIN SMALL LETTER T
    0x0075, # "u" LATIN SMALL LETTER U
    0x0076, # "v" LATIN SMALL LETTER V
    0x0077, # "w" LATIN SMALL LETTER W
    0x0078, # "x" LATIN SMALL LETTER X
    0x0079, # "y" LATIN SMALL LETTER Y
    0x007a, # "z" LATIN SMALL LETTER Z
    0x007b, # "{" LEFT CURLY BRACKET
    0x007c, # "|" VERTICAL LINE
    0x007d, # "}" RIGHT CURLY BRACKET
    0x007e, # "~" TILDE
    0x2302, # "⌂" HOUSE
    0x00c7, # "Ç" LATIN CAPITAL LETTER C WITH CEDILLA
    0x00fc, # "ü" LATIN SMALL LETTER U WITH DIAERESIS
    0x00e9, # "é" LATIN SMALL LETTER E WITH ACUTE
    0x00e2, # "â" LATIN SMALL LETTER A WITH CIRCUMFLEX
    0x00e4, # "ä" LATIN SMALL LETTER A WITH DIAERESIS
    0x00e0, # "à" LATIN SMALL LETTER A WITH GRAVE
    0x00e5, # "å" LATIN SMALL LETTER A WITH RING ABOVE
    0x00e7, # "ç" LATIN SMALL LETTER C WITH CEDILLA
    0x00ea, # "ê" LATIN SMALL LETTER E WITH CIRCUMFLEX
    0x00eb, # "ë" LATIN SMALL LETTER E WITH DIAERESIS
    0x00e8, # "è" LATIN SMALL LETTER E WITH GRAVE
    0x00ef, # "ï" LATIN SMALL LETTER I WITH DIAERESIS
    0x00ee, # "î" LATIN SMALL LETTER I WITH CIRCUMFLEX
    0x00ec, # "ì" LATIN SMALL LETTER I WITH GRAVE
    0x00c4, # "Ä" LATIN CAPITAL LETTER A WITH DIAERESIS
    0x00c5, # "Å" LATIN CAPITAL LETTER A WITH RING ABOVE
    0x00c9, # "É" LATIN CAPITAL LETTER E WITH ACUTE
    0x00e6, # "æ" LATIN SMALL LETTER AE
    0x00c6, # "Æ" LATIN CAPITAL LETTER AE
    0x00f4, # "ô" LATIN SMALL LETTER O WITH CIRCUMFLEX
    0x00f6, # "ö" LATIN SMALL LETTER O WITH DIAERESIS
    0x00f2, # "ò" LATIN SMALL LETTER O WITH GRAVE
    0x00fb, # "û" LATIN SMALL LETTER U WITH CIRCUMFLEX
    0x00f9, # "ù" LATIN SMALL LETTER U WITH GRAVE
    0x00ff, # "ÿ" LATIN SMALL LETTER Y WITH DIAERESIS
    0x00d6, # "Ö" LATIN CAPITAL LETTER O WITH DIAERESIS
    0x00dc, # "Ü" LATIN CAPITAL LETTER U WITH DIAERESIS
    0x00a2, # "¢" CENT SIGN
    0x00a3, # "£" POUND SIGN
    0x00a5, # "¥" YEN SIGN
    0x20a7, # "₧" PESETA SIGN
    0x0192, # "ƒ" LATIN SMALL LETTER F WITH HOOK
    0x00e1, # "á" LATIN SMALL LETTER A WITH ACUTE
    0x00ed, # "í" LATIN SMALL LETTER I WITH ACUTE
    0x00f3, # "ó" LATIN SMALL LETTER O WITH ACUTE
    0x00fa, # "ú" LATIN SMALL LETTER U WITH ACUTE
    0x00f1, # "ñ" LATIN SMALL LETTER N WITH TILDE
    0x00d1, # "Ñ" LATIN CAPITAL LETTER N WITH TILDE
    0x00aa, # "ª" FEMININE ORDINAL INDICATOR
    0x00ba, # "º" MASCULINE ORDINAL INDICATOR
    0x00bf, # "¿" INVERTED QUESTION MARK
    0x2310, # "⌐" REVERSED NOT SIGN
    0x00ac, # "¬" NOT SIGN
    0x00bd, # "½" VULGAR FRACTION ONE HALF
    0x00bc, # "¼" VULGAR FRACTION ONE QUARTER
    0x00a1, # "¡" INVERTED EXCLAMATION MARK
    0x00ab, # "«" LEFT-POINTING DOUBLE ANGLE QUOTATION MARK
    0x00bb, # "»" RIGHT-POINTING DOUBLE ANGLE QUOTATION MARK
    0x2591, # "░" LIGHT SHADE
    0x2592, # "▒" MEDIUM SHADE
    0x2593, # "▓" DARK SHADE
    0x2502, # "│" BOX DRAWINGS LIGHT VERTICAL
    0x2524, # "┤" BOX DRAWINGS LIGHT VERTICAL AND LEFT
    0x2561, # "╡" BOX DRAWINGS VERTICAL SINGLE AND LEFT DOUBLE
    0x2562, # "╢" BOX DRAWINGS VERTICAL DOUBLE AND LEFT SINGLE
    0x2556, # "╖" BOX DRAWINGS DOWN DOUBLE AND LEFT SINGLE
    0x2555, # "╕" BOX DRAWINGS DOWN SINGLE AND LEFT DOUBLE
    0x2563, # "╣" BOX DRAWINGS DOUBLE VERTICAL AND LEFT
    0x2551, # "║" BOX DRAWINGS DOUBLE VERTICAL
    0x2557, # "╗" BOX DRAWINGS DOUBLE DOWN AND LEFT
    0x255d, # "╝" BOX DRAWINGS DOUBLE UP AND LEFT
    0x255c, # "╜" BOX DRAWINGS UP DOUBLE AND LEFT SINGLE
    0x255b, # "╛" BOX DRAWINGS UP SINGLE AND LEFT DOUBLE
    0x2510, # "┐" BOX DRAWINGS LIGHT DOWN AND LEFT
    0x2514, # "└" BOX DRAWINGS LIGHT UP AND RIGHT
    0x2534, # "┴" BOX DRAWINGS LIGHT UP AND HORIZONTAL
    0x252c, # "┬" BOX DRAWINGS LIGHT DOWN AND HORIZONTAL
    0x251c, # "├" BOX DRAWINGS LIGHT VERTICAL AND RIGHT
    0x2500, # "─" BOX DRAWINGS LIGHT HORIZONTAL
    0x253c, # "┼" BOX DRAWINGS LIGHT VERTICAL AND HORIZONTAL
    0x255e, # "╞" BOX DRAWINGS VERTICAL SINGLE AND RIGHT DOUBLE
    0x255f, # "╟" BOX DRAWINGS VERTICAL DOUBLE AND RIGHT SINGLE
    0x255a, # "╚" BOX DRAWINGS DOUBLE UP AND RIGHT
    0x2554, # "╔" BOX DRAWINGS DOUBLE DOWN AND RIGHT
    0x2569, # "╩" BOX DRAWINGS DOUBLE UP AND HORIZONTAL
    0x2566, # "╦" BOX DRAWINGS DOUBLE DOWN AND HORIZONTAL
    0x2560, # "╠" BOX DRAWINGS DOUBLE VERTICAL AND RIGHT
    0x2550, # "═" BOX DRAWINGS DOUBLE HORIZONTAL
    0x256c, # "╬" BOX DRAWINGS DOUBLE VERTICAL AND HORIZONTAL
    0x2567, # "╧" BOX DRAWINGS UP SINGLE AND HORIZONTAL DOUBLE
    0x2568, # "╨" BOX DRAWINGS UP DOUBLE AND HORIZONTAL SINGLE
    0x2564, # "╤" BOX DRAWINGS DOWN SINGLE AND HORIZONTAL DOUBLE
    0x2565, # "╥" BOX DRAWINGS DOWN DOUBLE AND HORIZONTAL SINGLE
    0x2559, # "╙" BOX DRAWINGS UP DOUBLE AND RIGHT SINGLE
    0x2558, # "╘" BOX DRAWINGS UP SINGLE AND RIGHT DOUBLE
    0x2552, # "╒" BOX DRAWINGS DOWN SINGLE AND RIGHT DOUBLE
    0x2553, # "╓" BOX DRAWINGS DOWN DOUBLE AND RIGHT SINGLE
    0x256b, # "╫" BOX DRAWINGS VERTICAL DOUBLE AND HORIZONTAL SINGLE
    0x256a, # "╪" BOX DRAWINGS VERTICAL SINGLE AND HORIZONTAL DOUBLE
    0x2518, # "┘" BOX DRAWINGS LIGHT UP AND LEFT
    0x250c, # "┌" BOX DRAWINGS LIGHT DOWN AND RIGHT
    0x2588, # "█" FULL BLOCK
    0x2584, # "▄" LOWER HALF BLOCK
    0x258c, # "▌" LEFT HALF BLOCK
    0x2590, # "▐" RIGHT HALF BLOCK
    0x2580, # "▀" UPPER HALF BLOCK
    0x03b1, # "α" GREEK SMALL LETTER ALPHA
    0x00df, # "ß" LATIN SMALL LETTER SHARP S
    0x0393, # "Γ" GREEK CAPITAL LETTER GAMMA
    0x03c0, # "π" GREEK SMALL LETTER PI
    0x03a3, # "Σ" GREEK CAPITAL LETTER SIGMA
    0x03c3, # "σ" GREEK SMALL LETTER SIGMA
    0x00b5, # "µ" MICRO SIGN
    0x03c4, # "τ" GREEK SMALL LETTER TAU
    0x03a6, # "Φ" GREEK CAPITAL LETTER PHI
    0x0398, # "Θ" GREEK CAPITAL LETTER THETA
    0x03a9, # "Ω" GREEK CAPITAL LETTER OMEGA
    0x03b4, # "δ" GREEK SMALL LETTER DELTA
    0x221e, # "∞" INFINITY
    0x03c6, # "φ" GREEK SMALL LETTER PHI
    0x03b5, # "ε" GREEK SMALL LETTER EPSILON
    0x2229, # "∩" INTERSECTION
    0x2261, # "≡" IDENTICAL TO
    0x00b1, # "±" PLUS-MINUS SIGN
    0x2265, # "≥" GREATER-THAN OR EQUAL TO
    0x2264, # "≤" LESS-THAN OR EQUAL TO
    0x2320, # "⌠" TOP HALF INTEGRAL
    0x2321, # "⌡" BOTTOM HALF INTEGRAL
    0x00f7, # "÷" DIVISION SIGN
    0x2248, # "≈" ALMOST EQUAL TO
    0x00b0, # "°" DEGREE SIGN
    0x2219, # "∙" BULLET OPERATOR
    0x00b7, # "·" MIDDLE DOT
    0x221a, # "√" SQUARE ROOT
    0x207f, # "ⁿ" SUPERSCRIPT LATIN SMALL LETTER N
    0x00b2, # "²" SUPERSCRIPT TWO
    0x25a0, # "■" BLACK SQUARE
    0x00a0, # " " NO-BREAK SPACE
]

# Print Out Code Page 437 (mostly for fun)
for i in range(0, 8):
    print(''.join([(chr(k) if k is not None else ' ')
        for k in keys[i * 32:i * 32 + 32]]))

# Sort Out Out the Unicode Data ==============================================

# Make Key Value Pairs
kvs = [KeyValue(k, v) for v, k in enumerate(keys) if k is not None]
kvs.sort()

# Sort Into Ranges
ranges = get_ranges(kvs)
ranges.sort(key=lambda r: r.kvs[0].key)
ranges.sort(key=lambda r: len(r), reverse=True)
print('All Ranges ====================================================================')
for r in ranges:
    print(r)

# Separate Out the Contiguous Ranges from Ranges to Add to the Hash Table
contiguous_ranges = []
bucket_count = 0
ranges_to_hash = []
for r in ranges:
    offset = r.same_offset()
    if offset is not None and len(r) > 1:
        contiguous_ranges.append(r)
    else: # Hash it
        bucket_count += len(r)
        ranges_to_hash.append(r)

max_bucket_length = 0
buckets = {}
for r in ranges_to_hash:
    for kv in r.kvs:
        m = kv.key % bucket_count # Hash is Simple Mod With Bucket Count
        if m not in buckets:
            buckets[m] = []
        buckets[m].append(kv)
        l = len(buckets[m])
        max_bucket_length = max(len(buckets[m]), max_bucket_length)

print('Contiguous Ranges =============================================================')
for r in contiguous_ranges:
    print(r)

print('Hashed Ranges =================================================================')
print('bucket_count:', bucket_count)
print('max_bucket_length: ', max_bucket_length)
if (max_bucket_length > 255):
    sys.exit('max_bucket_length is too large')

print('size: ', max_bucket_length * bucket_count)
max_hash_used = 0
for this_hash in range(0, bucket_count):
    if this_hash in buckets:
        print('0x{:08x}'.format(this_hash), buckets[this_hash])
        max_hash_used = this_hash
print('max_hash_used:', hex(max_hash_used))

# Code Generation ============================================================

with open(zig_file, "w") as f:
    def fprint(*args, **kwargs):
        print(*args, **kwargs, file=f)

    fprint('''// Generated by scripts/codegen/code_page_437.py
// This is data just used by cga_console.zig
''')

    fprint('pub const bucket_count: u16 = {};\n'.format(bucket_count));
    fprint('pub const max_bucket_length: u16 = {};\n'.format(max_bucket_length));
    fprint('pub const max_hash_used: u16 = {};\n'.format(max_hash_used));

    fprint('pub const hash_table = [_]u32 {')
    for this_hash in range(0, max_hash_used + 1):
        fprint('   ', end='')
        bucket = buckets[this_hash] if this_hash in buckets else []
        for kv in bucket:
            fprint(' 0x{:08x},'.format(
                0x01000000 | (kv.value << 16) | kv.key), end = '')

        for i in range(0, max_bucket_length - len(bucket)):
            fprint(' 0x00000000,', end = '')
        fprint('')

    fprint('''};

pub fn contiguous_ranges(c: u16) ?u8 {''')

    for r in contiguous_ranges:
        offset = r.same_offset()
        return_string = 'return @intCast(u8, c{})'.format(
            ' - 0x{:04x}'.format(offset) if offset else '')
        base = r.kvs[0].key
        fprint('    if (c >= 0x{:04x} and c <= 0x{:04x}) {};'.format(
            base, base + len(r) - 1, return_string))

    fprint('''
    return null;
}''')
