# =============================================================================
# Script for generating kernel/keys.zig and libs/georgios/keys.zig
# =============================================================================

import string

def k(name, char):
    return ('Key_' + name, 'null' if char is None else '\'' + char + '\'')

keys = []

# Letters and Numbers
keys.extend([k(c, c) for c in string.ascii_lowercase])
keys.extend([k(c, c) for c in string.ascii_uppercase])
keys.extend([k(c, c) for c in string.digits])
keys.extend([k('Keypad' + c, c) for c in string.digits])

# Keys with Printable Symbols
keys.extend([k(*pair) for pair in [
    ('Enter', '\\n'),
    ('KeypadEnter', '\\n'),
    ('Tab', '\\t'),
    ('Backspace', '\\x08'),
    ('Space', ' '),
    ('Slash', '/'),
    ('KeypadSlash', '/'),
    ('Backslash', '\\\\'),
    ('Period', '.'),
    ('KeypadPeriod', '.'),
    ('Question', '?'),
    ('Exclamation', '!'),
    ('Comma', ','),
    ('Colon', ':'),
    ('SemiColon', ';'),
    ('BackTick', '`'),
    ('SingleQuote', '\\\''),
    ('DoubleQuote', '"'),
    ('Asterisk', '*'),
    ('KeypadAsterisk', '*'),
    ('At', '@'),
    ('Ampersand', '&'),
    ('Percent', '%'),
    ('Caret', '^'),
    ('Pipe', '|'),
    ('Tilde', '~'),
    ('Underscore', '_'),
    ('Pound', '#'),
    ('Dollar', '$'),
    ('Plus', '+'),
    ('KeypadPlus', '+'),
    ('Minus', '-'),
    ('KeypadMinus', '-'),
    ('Equals', '='),
    ('GreaterThan', '>'),
    ('LessThan', '<'),
    ('LeftBrace', '{'),
    ('RightBrace', '}'),
    ('LeftSquareBracket', '['),
    ('RightSquareBracket', ']'),
    ('LeftParentheses', '('),
    ('RightParentheses', ')'),
]])

# Keys with no Printable Symbols
keys.extend([k(name, None) for name in [
    'Escape',
    'LeftShift',
    'RightShift',
    'LeftAlt',
    'RightAlt',
    'LeftControl',
    'RightControl',
    'CapsLock',
    'NumberLock',
    'ScrollLock',
    'F1',
    'F2',
    'F3',
    'F4',
    'F5',
    'F6',
    'F7',
    'F8',
    'F9',
    'F10',
    'F11',
    'F12',
    'CursorLeft',
    'CursorRight',
    'CursorUp',
    'CursorDown',
    'PageUp',
    'PageDown',
    'AcpiPower',
    'AcpiSleep',
    'AcpiWake',
    'Home',
    'End',
    'Insert',
    'Delete',
    'PrintScreen',
    'Pause',
]])

# Generate Key Definitions
with open('libs/georgios/keys.zig', 'w') as f:
    print('''\
// Generated by scripts/codegen/keys.py

pub const Key = enum {''', file=f)
    for pair in keys:
        print('    ' + pair[0] + ',', file=f)
    print('};', file=f)

# Generate Key to Character Function
with open('kernel/keys.zig', 'w') as f:
    print('''\
// Generated by scripts/codegen/keys.py

const Key = @import("georgios").keyboard.Key;

pub fn key_to_char(key: Key) ?u8 {
    return chars_table[@enumToInt(key)];
}

const chars_table = [_]?u8 {''', file=f)
    for pair in keys:
        print('    ' + pair[1] + ',', file=f)
    print('};', file=f)
