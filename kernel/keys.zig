// Generated by scripts/codegen/keys.py

const Key = @import("georgios").keyboard.Key;

pub fn key_to_char(key: Key) ?u8 {
    return chars_table[@enumToInt(key)];
}

const chars_table = [_]?u8 {
    'a',
    'b',
    'c',
    'd',
    'e',
    'f',
    'g',
    'h',
    'i',
    'j',
    'k',
    'l',
    'm',
    'n',
    'o',
    'p',
    'q',
    'r',
    's',
    't',
    'u',
    'v',
    'w',
    'x',
    'y',
    'z',
    'A',
    'B',
    'C',
    'D',
    'E',
    'F',
    'G',
    'H',
    'I',
    'J',
    'K',
    'L',
    'M',
    'N',
    'O',
    'P',
    'Q',
    'R',
    'S',
    'T',
    'U',
    'V',
    'W',
    'X',
    'Y',
    'Z',
    '0',
    '1',
    '2',
    '3',
    '4',
    '5',
    '6',
    '7',
    '8',
    '9',
    '0',
    '1',
    '2',
    '3',
    '4',
    '5',
    '6',
    '7',
    '8',
    '9',
    '\n',
    '\n',
    '\t',
    '\x08',
    ' ',
    '/',
    '/',
    '\\',
    '.',
    '.',
    '?',
    '!',
    ',',
    ':',
    ';',
    '`',
    '\'',
    '"',
    '*',
    '*',
    '@',
    '&',
    '%',
    '^',
    '|',
    '~',
    '_',
    '#',
    '$',
    '+',
    '+',
    '-',
    '-',
    '=',
    '>',
    '<',
    '{',
    '}',
    '[',
    ']',
    '(',
    ')',
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
};
