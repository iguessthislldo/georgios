import string

codes = []
prefix = 'PS2_SCAN_CODE_'
char = lambda x: "'{}'".format(x)

alpha_raw = list(zip([
    0x1E, 0x30, 0x2e, 0x20, 0x12, 0x21, 0x22, 0x23,
    0x17, 0x24, 0x25, 0x26, 0x32, 0x31, 0x18, 0x19,
    0x10, 0x13, 0x1F, 0x14, 0x16, 0x2f, 0x11, 0x2d,
    0x15, 0x2c],
    string.ascii_uppercase))
codes.extend(list(map(lambda x: (x[0], x[1], char(x[1])), alpha_raw)))

digits_raw = list(zip([
    0xb, 0x02, 0x03, 0x4, 0x5, 0x6, 0x7, 0x8, 0x9, 0xa],
    string.digits))
codes.extend(list(map(lambda x: (x[0], x[1], char(x[1])), digits_raw)))

control_raw = [
    (0x1, 'ESCAPE'),
    (0x2a, 'LEFT_SHIFT'),
    (0x36, 'RIGHT_SHIFT'),
    (0x0E, 'BACKSPACE'),
]
codes.extend(list(map(lambda x: (x[0], x[1], 0), control_raw)))

codes.append((0x1c, 'ENTER', char('\\n')))
codes.append((0x39, 'SPACE', char(' ')))

table = [0] * 256
for i in codes:
    types = [
        (i[0], prefix + i[1] + "_PRESSED", 0),
        (i[0] | 128, prefix + i[1] + "_RELEASED", i[2])
    ]
    for code, name, char in types:
        print('#define {0} 0x{1:02x}'.format(name, code))
        table[code] = char

print('\nchar ps2_scan_code_chars[] = {')
print(',\n'.join(map(lambda x: '    ' + str(x), table)), end='\n};\n')
