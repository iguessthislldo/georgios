# =============================================================================
# Script for generating kernel/platform/ps2_scan_codes.zig
# =============================================================================

codes = [
    ([0x01], 'Escape', None, 'Pressed'),
    ([0x02], '1', 'Exclamation', 'Pressed'),
    ([0x03], '2', 'At', 'Pressed'),
    ([0x04], '3', 'Pound', 'Pressed'),
    ([0x05], '4', 'Dollar', 'Pressed'),
    ([0x06], '5', 'Percent', 'Pressed'),
    ([0x07], '6', 'Caret', 'Pressed'),
    ([0x08], '7', 'Ampersand', 'Pressed'),
    ([0x09], '8', 'Asterisk', 'Pressed'),
    ([0x0a], '9', 'LeftParentheses', 'Pressed'),
    ([0x0b], '0', 'RightParentheses', 'Pressed'),
    ([0x0c], 'Minus', 'Underscore', 'Pressed'),
    ([0x0d], 'Equals', 'Plus', 'Pressed'),
    ([0x0e], 'Backspace', None, 'Pressed'),
    ([0x0f], 'Tab', None, 'Pressed'),
    ([0x10], 'q', 'Q', 'Pressed'),
    ([0x11], 'w', 'W', 'Pressed'),
    ([0x12], 'e', 'E', 'Pressed'),
    ([0x13], 'r', 'R', 'Pressed'),
    ([0x14], 't', 'T', 'Pressed'),
    ([0x15], 'y', 'Y', 'Pressed'),
    ([0x16], 'u', 'U', 'Pressed'),
    ([0x17], 'i', 'I', 'Pressed'),
    ([0x18], 'o', 'O', 'Pressed'),
    ([0x19], 'p', 'P', 'Pressed'),
    ([0x1a], 'LeftSquareBracket', 'LeftBrace', 'Pressed'),
    ([0x1b], 'RightSquareBracket', 'RightBrace', 'Pressed'),
    ([0x1c], 'Enter', None, 'Pressed'),
    ([0x1d], 'LeftControl', None, 'Pressed'),
    ([0x1e], 'a', 'A', 'Pressed'),
    ([0x1f], 's', 'S', 'Pressed'),
    ([0x20], 'd', 'D', 'Pressed'),
    ([0x21], 'f', 'F', 'Pressed'),
    ([0x22], 'g', 'G', 'Pressed'),
    ([0x23], 'h', 'H', 'Pressed'),
    ([0x24], 'j', 'J', 'Pressed'),
    ([0x25], 'k', 'K', 'Pressed'),
    ([0x26], 'l', 'L', 'Pressed'),
    ([0x27], 'SemiColon', 'Colon', 'Pressed'),
    ([0x28], 'SingleQuote', 'DoubleQuote', 'Pressed'),
    ([0x29], 'BackTick', 'Tilde', 'Pressed'),
    ([0x2a], 'LeftShift', None, 'Pressed'),
    ([0x2b], 'Backslash', 'Pipe', 'Pressed'),
    ([0x2c], 'z', 'Z', 'Pressed'),
    ([0x2d], 'x', 'X', 'Pressed'),
    ([0x2e], 'c', 'C', 'Pressed'),
    ([0x2f], 'v', 'V', 'Pressed'),
    ([0x30], 'b', 'B', 'Pressed'),
    ([0x31], 'n', 'N', 'Pressed'),
    ([0x32], 'm', 'M', 'Pressed'),
    ([0x33], 'Comma', 'LessThan', 'Pressed'),
    ([0x34], 'Period', 'GreaterThan', 'Pressed'),
    ([0x35], 'Slash', 'Question', 'Pressed'),
    ([0x36], 'RightShift', None, 'Pressed'),
    ([0x37], 'KeypadAsterisk', None, 'Pressed'),
    ([0x38], 'LeftAlt', None, 'Pressed'),
    ([0x39], 'Space', None, 'Pressed'),
    ([0x3a], 'CapsLock', None, 'Pressed'),
    ([0x3b], 'F1', None, 'Pressed'),
    ([0x3c], 'F2', None, 'Pressed'),
    ([0x3d], 'F3', None, 'Pressed'),
    ([0x3e], 'F4', None, 'Pressed'),
    ([0x3f], 'F5', None, 'Pressed'),
    ([0x40], 'F6', None, 'Pressed'),
    ([0x41], 'F7', None, 'Pressed'),
    ([0x42], 'F8', None, 'Pressed'),
    ([0x43], 'F9', None, 'Pressed'),
    ([0x44], 'F10', None, 'Pressed'),
    ([0x45], 'NumberLock', None, 'Pressed'),
    ([0x46], 'ScrollLock', None, 'Pressed'),
    ([0x47], 'Keypad7', None, 'Pressed'),
    ([0x48], 'Keypad8', None, 'Pressed'),
    ([0x49], 'Keypad9', None, 'Pressed'),
    ([0x4a], 'KeypadMinus', None, 'Pressed'),
    ([0x4b], 'Keypad4', None, 'Pressed'),
    ([0x4c], 'Keypad5', None, 'Pressed'),
    ([0x4d], 'Keypad6', None, 'Pressed'),
    ([0x4e], 'KeypadPlus', None, 'Pressed'),
    ([0x4f], 'Keypad1', None, 'Pressed'),
    ([0x50], 'Keypad2', None, 'Pressed'),
    ([0x51], 'Keypad3', None, 'Pressed'),
    ([0x52], 'Keypad0', None, 'Pressed'),
    ([0x53], 'KeypadPeriod', None, 'Pressed'),
    ([0x57], 'F11', None, 'Pressed'),
    ([0x58], 'F12', None, 'Pressed'),

    ([0x81], 'Escape', None, 'Released'),
    ([0x82], '1', 'Exclamation', 'Released'),
    ([0x83], '2', 'At', 'Released'),
    ([0x84], '3', 'Pound', 'Released'),
    ([0x85], '4', 'Dollar', 'Released'),
    ([0x86], '5', 'Percent', 'Released'),
    ([0x87], '6', 'Caret', 'Released'),
    ([0x88], '7', 'Ampersand', 'Released'),
    ([0x89], '8', 'Asterisk', 'Released'),
    ([0x8a], '9', 'LeftParentheses', 'Released'),
    ([0x8b], '0', 'RightParentheses', 'Released'),
    ([0x8c], 'Minus', 'Underscore', 'Released'),
    ([0x8d], 'Equals', 'Plus', 'Released'),
    ([0x8e], 'Backspace', None, 'Released'),
    ([0x8f], 'Tab', None, 'Released'),
    ([0x90], 'q', 'Q', 'Released'),
    ([0x91], 'w', 'W', 'Released'),
    ([0x92], 'e', 'E', 'Released'),
    ([0x93], 'r', 'R', 'Released'),
    ([0x94], 't', 'T', 'Released'),
    ([0x95], 'y', 'Y', 'Released'),
    ([0x96], 'u', 'U', 'Released'),
    ([0x97], 'i', 'I', 'Released'),
    ([0x98], 'o', 'O', 'Released'),
    ([0x99], 'p', 'P', 'Released'),
    ([0x9a], 'LeftSquareBracket', 'LeftBrace', 'Released'),
    ([0x9b], 'RightSquareBracket', 'RightBrace', 'Released'),
    ([0x9c], 'Enter', None, 'Released'),
    ([0x9d], 'LeftControl', None, 'Released'),
    ([0x9e], 'a', 'A', 'Released'),
    ([0x9f], 's', 'S', 'Released'),
    ([0xa0], 'd', 'D', 'Released'),
    ([0xa1], 'f', 'F', 'Released'),
    ([0xa2], 'g', 'G', 'Released'),
    ([0xa3], 'h', 'H', 'Released'),
    ([0xa4], 'j', 'J', 'Released'),
    ([0xa5], 'k', 'K', 'Released'),
    ([0xa6], 'l', 'L', 'Released'),
    ([0xa7], 'SemiColon', 'Colon', 'Released'),
    ([0xa8], 'SingleQuote', 'DoubleQuote', 'Released'),
    ([0xa9], 'BackTick', 'Tilde', 'Released'),
    ([0xaa], 'LeftShift', None, 'Released'),
    ([0xab], 'Backslash', 'Pipe', 'Released'),
    ([0xac], 'z', 'Z', 'Released'),
    ([0xad], 'x', 'X', 'Released'),
    ([0xae], 'c', 'C', 'Released'),
    ([0xaf], 'v', 'V', 'Released'),
    ([0xb0], 'b', 'B', 'Released'),
    ([0xb1], 'n', 'N', 'Released'),
    ([0xb2], 'm', 'M', 'Released'),
    ([0xb3], 'Comma', 'LessThan', 'Released'),
    ([0xb4], 'Period', 'GreaterThan', 'Released'),
    ([0xb5], 'Slash', 'Question', 'Released'),
    ([0xb6], 'RightShift', None, 'Released'),
    ([0xb7], 'KeypadAsterisk', None, 'Released'),
    ([0xb8], 'LeftAlt', None, 'Released'),
    ([0xb9], 'Space', None, 'Released'),
    ([0xba], 'CapsLock', None, 'Released'),
    ([0xbb], 'F1', None, 'Released'),
    ([0xbc], 'F2', None, 'Released'),
    ([0xbd], 'F3', None, 'Released'),
    ([0xbe], 'F4', None, 'Released'),
    ([0xbf], 'F5', None, 'Released'),
    ([0xc0], 'F6', None, 'Released'),
    ([0xc1], 'F7', None, 'Released'),
    ([0xc2], 'F8', None, 'Released'),
    ([0xc3], 'F9', None, 'Released'),
    ([0xc4], 'F10', None, 'Released'),
    ([0xc5], 'NumberLock', None, 'Released'),
    ([0xc6], 'ScrollLock', None, 'Released'),
    ([0xc7], 'Keypad7', None, 'Released'),
    ([0xc8], 'Keypad8', None, 'Released'),
    ([0xc9], 'Keypad9', None, 'Released'),
    ([0xca], 'KeypadMinus', None, 'Released'),
    ([0xcb], 'Keypad4', None, 'Released'),
    ([0xcc], 'Keypad5', None, 'Released'),
    ([0xcd], 'Keypad6', None, 'Released'),
    ([0xce], 'KeypadPlus', None, 'Released'),
    ([0xcf], 'Keypad1', None, 'Released'),
    ([0xd0], 'Keypad2', None, 'Released'),
    ([0xd1], 'Keypad3', None, 'Released'),
    ([0xd2], 'Keypad0', None, 'Released'),
    ([0xd3], 'KeypadPeriod', None, 'Released'),
    ([0xd7], 'F11', None, 'Released'),
    ([0xd8], 'F12', None, 'Released'),

    ([0xe0, 0x1c], 'KeypadEnter', None, 'Pressed'),
    ([0xe0, 0x1d], 'RightControl', None, 'Pressed'),
    ([0xe0, 0x35], 'KeypadSlash', None, 'Pressed'),
    ([0xe0, 0x38], 'RightAlt', None, 'Pressed'),
    ([0xe0, 0x47], 'Home', None, 'Pressed'),
    ([0xe0, 0x48], 'CursorUp', None, 'Pressed'),
    ([0xe0, 0x49], 'PageUp', None, 'Pressed'),
    ([0xe0, 0x4b], 'CursorLeft', None, 'Pressed'),
    ([0xe0, 0x4d], 'CursorRight', None, 'Pressed'),
    ([0xe0, 0x4f], 'End', None, 'Pressed'),
    ([0xe0, 0x50], 'CursorDown', None, 'Pressed'),
    ([0xe0, 0x51], 'PageDown', None, 'Pressed'),
    ([0xe0, 0x52], 'Insert', None, 'Pressed'),
    ([0xe0, 0x53], 'Delete', None, 'Pressed'),
    ([0xe0, 0x5e], 'AcpiPower', None, 'Pressed'),
    ([0xe0, 0x5f], 'AcpiSleep', None, 'Pressed'),
    ([0xe0, 0x63], 'AcpiWake', None, 'Pressed'),

    ([0xe0, 0x9c], 'KeypadEnter', None, 'Released'),
    ([0xe0, 0x9d], 'RightControl', None, 'Released'),
    ([0xe0, 0xb5], 'KeypadSlash', None, 'Released'),
    ([0xe0, 0xb8], 'RightAlt', None, 'Released'),
    ([0xe0, 0xc7], 'Home', None, 'Released'),
    ([0xe0, 0xc8], 'CursorUp', None, 'Released'),
    ([0xe0, 0xc9], 'PageUp', None, 'Released'),
    ([0xe0, 0xcb], 'CursorLeft', None, 'Released'),
    ([0xe0, 0xcd], 'CursorRight', None, 'Released'),
    ([0xe0, 0xcf], 'End', None, 'Released'),
    ([0xe0, 0xd0], 'CursorDown', None, 'Released'),
    ([0xe0, 0xd1], 'PageDown', None, 'Released'),
    ([0xe0, 0xd2], 'Insert', None, 'Released'),
    ([0xe0, 0xd3], 'Delete', None, 'Released'),
    ([0xe0, 0xde], 'AcpiPower', None, 'Released'),
    ([0xe0, 0xdf], 'AcpiSleep', None, 'Released'),
    ([0xe0, 0xe3], 'AcpiWake', None, 'Released'),
]

one_byte_codes = []
two_byte_codes = []

for code in codes:
    l = len(code[0])
    if l == 1:
        one_byte_codes.append(code)
    elif l == 2:
        two_byte_codes.append(code)
    else:
        raise ValueError('Code must have one or two bytes')

def key(value):
    if value is None:
        return 'null'
    return '.Key_' + value

def kind(value):
    if value is None:
        return 'null'
    return '.' + value

with open('kernel/platform/ps2_scan_codes.zig', 'w') as f:
    print('''\
// Generated by scripts/codegen/scan_codes.py

const georgios = @import("georgios");
const kb = georgios.keyboard;

pub const Entry = struct {
    key: ?kb.Key,
    shifted_key: ?kb.Key,
    kind: ?kb.Kind,
};''', file=f)

    def make_table(codes, index, name):
        table = [(None, None, None)] * 256
        print('\npub const', name, '= [256]Entry {', file=f)
        for code in codes:
            table[code[0][index]] = code[1:]
        for row in table:
            print('    Entry{{.key = {}, .shifted_key = {}, .kind = {}}},'.format(
                key(row[0]), key(row[1]), kind(row[2])), file=f)
        print('};', file=f)

    make_table(one_byte_codes, 0, 'one_byte')
    make_table(two_byte_codes, 1, 'two_byte')
