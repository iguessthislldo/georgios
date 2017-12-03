#include <print.h> // Header for this c file

#include <platform.h> // vargs
 
void print_nstring(const char * string, u32 size) {
	for (u32 i = 0; i < size; i++) {
		print_char(string[i]);
    }
}
 
void print_string(const char * string) {
    u32 i = 0;
	for (char c = string[i]; c; c = string[++i]) {
		print_char(c);
    }
}

void print_int_recurse(u32 value) {
    if (value) {
        u8 digit = value % 10;
        print_int_recurse(value / 10);
        print_char('0' + digit);
    }
}

void print_uint(u32 value) {
    if (!value) {
        print_char('0');
        return;
    }
    print_int_recurse(value);
}

void print_int(i32 value) {
    if (value < 0) {
        print_char('-');
        value = -value;
    }
    print_uint(value);
}

void print_nibble(u8 value) {
    value = value % 16;
    if (value < 10) {
        print_char('0' + value);
    } else {
        print_char('A' + value - 10);
    }
}

void print_hex_recurse(u32 value) {
    if (value) {
        print_hex_recurse(value / 16);
        print_nibble(value);
    }
}

void print_hex(u32 value) {
    print_char('0');
    print_char('x');
    if (!value) {
        print_char('0');
        return;
    }
    print_hex_recurse(value);
}

void print_byte(u8 value) {
    print_nibble(value >> 4);
    print_nibble(value);
}

void print_format(const char * format, ...) {
    va_list args;
    va_start(args, format);
    bool escape = false;
    char size = 'l';
    u32 i = 0;

    for (char c = format[i]; c != '\0'; c = format[++i]) {
        if (escape) {
            switch (c) {

            // Size
            case 'b':
            case 'h':
            case 'l':
                size = c;
                break;

            // Signed Ints
            case 'd':
                if (size == 'b') {
                    print_int(va_arg(args, i8));
                } else if (size == 's') {
                    print_int(va_arg(args, i16));
                } else {
                    print_int(va_arg(args, i32));
                }
                escape = false;
                break;

            // Unsigned Ints
            case 'u':
                if (size == 'b') {
                    print_uint(va_arg(args, u8));
                } else if (size == 's') {
                    print_uint(va_arg(args, u16));
                } else {
                    print_uint(va_arg(args, u32));
                }
                escape = false;
                break;

            // Hex
            case 'x':
                if (size == 'b') {
                    print_hex(va_arg(args, u8));
                } else if (size == 's') {
                    print_hex(va_arg(args, u16));
                } else {
                    print_hex(va_arg(args, u32));
                }
                escape = false;
                break;

            // Characters 
            case 'c':
                print_char(va_arg(args, char));
                escape = false;
                break;

            // Strings
            case 's':
                print_string(va_arg(args, char*));
                escape = false;
                break;

            // Percent Sign
            case '%':
                print_char('%');
                escape = false;
                break;

            // Print the pair if we don't know
            default:
                print_char('%');
                print_char(c);
                escape = false;
            }
        } else if (c == '%') {
            escape = true;
        } else {
            print_char(c);
        }
    }
}
