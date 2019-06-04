#include "print.h"

#include <stdarg.h> // va_* for print_format
#include <library.h> // isspace,  memcpy

void print_nstring(const char * string, u4 size) {
	for (u4 i = 0; i < size; i++) {
        if (string[i])
            print_char(string[i]);
        else break;
    }
}

void print_string(const char * string) {
    u4 i = 0;
	for (char c = string[i]; c; c = string[++i]) {
		print_char(c);
    }
}

void print_stripped_string(const char * string, u4 size) {
    u4 i;
    u4 keep = 0;
    for (i = 0; i < size && string[i]; i++) {
        if (!isspace(string[i])) keep = i + 1;
    }
	for (i = 0; i < keep; i++) {
        print_char(string[i]);
    }
}

void print_int_recurse(u4 value) {
    if (value) {
        u1 digit = value % 10;
        print_int_recurse(value / 10);
        print_char('0' + digit);
    }
}

void print_uint(u4 value) {
    if (!value) {
        print_char('0');
        return;
    }
    print_int_recurse(value);
}

void print_int(i4 value) {
    if (value < 0) {
        print_char('-');
        value = -value;
    }
    print_uint(value);
}

void print_int_sign(i4 value, bool show_positive) {
    if (value > 0 && show_positive) {
        print_char('+');
    }
    print_int(value);
}

void print_nibble(u1 value) {
    value = value % 16;
    if (value < 10) {
        print_char('0' + value);
    } else {
        print_char('A' + value - 10);
    }
}

void print_hex_recurse(u4 value) {
    if (value) {
        print_hex_recurse(value / 16);
        print_nibble(value);
    }
}

void print_hex(u4 value) {
    print_char('0');
    print_char('x');
    if (!value) {
        print_char('0');
        return;
    }
    print_hex_recurse(value);
}

void print_byte(u1 value) {
    print_nibble(value >> 4);
    print_nibble(value);
}

void print_format(const char * format, ...) {
    va_list args;
    va_start(args, format);
    bool escape = false;
    char type = 0;
    bool is_signed = false;
    bool show_positive = false;
    bool reset = false;
    u4 i = 0;

    for (char c = format[i]; c != '\0'; c = format[++i]) {
        if (escape) {
            if (c == '}') {
                switch (type) {

                // Decimal
                case 'd':
                    if (is_signed) {
                        print_int_sign(va_arg(args, i4), show_positive);
                    } else {
                        print_uint(va_arg(args, u4));
                    }
                    break;

                // Hexadecimal
                case 'x':
                    print_hex(va_arg(args, u4));
                    break;

                // Characters
                case 'c':
                    print_char(va_arg(args, u4));
                    break;

                // Strings
                case 's':
                    print_string(va_arg(args, char*));
                    break;

                default: // Nothing ...
                    break;
                }
                reset = true;
            } else switch (c) {
            case 'd':
            case 'x':
            case 'c':
            case 's':
                type = c;
                break;

            case '+':
                show_positive = true;
            case '-':
                is_signed = true;
                break;

            case '{':
                print_char('{');
                reset = true;
                break;

            default:
                reset = true;
            }
        } else if (c == '{') {
            escape = true;
        } else {
            print_char(c);
        }

        if (reset) {
            escape = false;
            type = 0;
            is_signed = false;
            show_positive = false;
            reset = false;
        }
    }
}

void print_dragon() {
    print_string(
"@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@**^^''~~~'^@@^*@*@@**@@@@@@@@@@@@\n"
"@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@*^^''~   , - ' '; ,@@b. '  -e@@@@@@@@@@@@\n"
"@@@@@@@@@@@@@@@@@@@@@@@@@*^'~      . '     . ' ,@@@@(  e@*@@@@@@@@@@@@@\n"
"@@@@@@@@@@@@@@@@@@@@@@^~         .       .   ' @@@@@@, ~^@@@@@@@@@@@@@@\n"
"@@@@@@@@@@@@@@@@@@@@~ ,e**@@*e,  ,e**e, .    ' '@@@@@@e,  '*@@@@@'^@@@@\n"
"@@@@@@@@@@@@@@@@@@',e@@@@@@@@@@ e@@@@@@       ' '*@@@@@@    @@@'   0@@@\n"
"@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@',e,     ;  ~^*^'    ;^~   ' 0@@@\n"
"@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@^''^@@e@@@   .'           ,'   .'  @@@@\n"
"@@@@@@@?@@@,@@@@@@@@@@@@@@@@@@@@'    '@@@@@ '         ,  ,e'  .    ;@@@\n"
"@@@@@@|\\@@' *_`@@@@@@@@@@@@@@@@@' ,&&,  ^@*'     ,  .  i^'@e, ,e@e  @@@\n"
"@@------*--->@@@@@@@@@@@@@@@@@' ,@@@@,          ;  ,& !,,@@@e@@@@ e@@@@\n"
"/` .  \\  .'@@@@@@@@@@@,~*@@*' ,@@@@@@e,   ',   e^~^@,   ~'@@@@@@,@@@@@@\n"
"@''@``@@''@``@@@@@@@@@@@, ~' ,e@@@@@@@@@*e*@*  ,@e  @@''@e,,@@@@@@@@@@@\n"
"@;'@`;@@;'@`;@@@@@@@@@@@@@@ee@@@@@@@@@@@@@@@' ,e@' ,e@' e@@@@@@@@@@@@@@\n"
"@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@' ,@' ,e@@e,,@@@@@@@@@@@@@@@@@\n"
"@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@~ ,@@@,,0@@@@@@@@@@@@@@@@@@@@@@\n"
    );
}

void print_data(u1 * ptr, u4 size) {
    for (u4 i = 0; i < size; i++) {
        print_byte(ptr[i]);
        if (!((i+1) % 16)) {
            print_char('\n');
        } else {
            if (!((i+1) % 8)) {
                print_char(' ');
            }
            print_char(' ');
        }
    }
}

// Recursion probably isn't necessary here... but whatever
size_t sprint_int_recurse(u4 value, char * output) {
    size_t rv = 0;
    if (value) {
        u1 digit = value % 10;
        rv = sprint_int_recurse(value / 10, output ? (output + 1) : 0) + 1;
        if (output) {
            *output = '0' + digit;
        }
    }
    return rv;
}

size_t sprint_uint(u4 value, char * output) {
    if (!value) {
        if (output) {
            *output = '0';
        }
        return 1;
    }
    return sprint_int_recurse(value, output);
}

size_t sprint_size(mem_t size, char * buffer, size_t buffer_size) {
	size_t kib_size = size >> 10;
	size_t mib_size = kib_size >> 10;
	size_t gib_size = mib_size >> 10;
    size_t len;
	if (gib_size) {
#define L 4
        len = sprint_uint(gib_size, 0);
        if ((len + L) > buffer_size) return 0;
        sprint_uint(gib_size, buffer);
        memcpy(buffer + len, " GiB", L);
        len += L;
	} else if (mib_size) {
        len = sprint_uint(mib_size, 0);
        if ((len + L) > buffer_size) return 0;
        sprint_uint(mib_size, buffer);
        memcpy(buffer + len, " MiB", L);
        len += L;
	} else if (kib_size) {
        len = sprint_uint(kib_size, 0);
        if ((len + L) > buffer_size) return 0;
        sprint_uint(kib_size, buffer);
        memcpy(buffer + len, " KiB", L);
        len += L;
	} else {
#undef L
#define L 2
        len = sprint_uint(size, 0);
        if ((len + L) > buffer_size) return 0;
        sprint_uint(size, buffer);
        memcpy(buffer + len, " B", L);
        len += L;
#undef L
	}
    return len;
}
