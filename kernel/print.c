#include <print.h> // Header for this c file

#include <platform.h> // vargs
 
void print_nstring(const char * string, u4 size) {
	for (u4 i = 0; i < size; i++) {
		print_char(string[i]);
    }
}
 
void print_string(const char * string) {
    u4 i = 0;
	for (char c = string[i]; c; c = string[++i]) {
		print_char(c);
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
"@@@|@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@',e,     ;  ~^*^'    ;^~   ' 0@@@\n"
"@@@|@@@@@@@@@@@@@@@@@@@@@@@@@@@@^''^@@e@@@   .'           ,'   .'  @@@@\n"
"@@@+@\\@@@@@@@@@@@@@@@@@@@@@@@@@'    '@@@@@ '         ,  ,e'  .    ;@@@@\n"
"@@@\\\\.G_.*=.@@@@@@@@@@@@@@@@@@' ,&&,  ^@*'     ,  .  i^'@e, ,e@e  @@@@@\n"
"@@@@`(H'/.\\|@@@@@@@@@@@@@@@@@' ,@@@@,          ;  ,& !,,@@@e@@@@ e@@@@@\n"
"@@@@@.>' (_--.@@@@@@@@,~*@@*' ,@@@@@@e,   ',   e^~^@,   ~'@@@@@@,@@@@@@\n"
"@@_=/d   ,^\\@@@@@@@@@@@, ~' ,e@@@@@@@@@*e*@*  ,@e  @@''@e,,@@@@@@@@@@@@\n"
"@~~@j\\)-'@@@'@@@@@@@@@@@@@ee@@@@@@@@@@@@@@@' ,e@' ,e@' e@@@@@@@@@@@@@@@@\n"
"@@@@/ |@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@' ,@' ,e@@e,,@@@@@@@@@@@@@@@@@\n"
"@@@'  '@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@~ ,@@@,,0@@@@@@@@@@@@@@@@@@@@@@\n"
    );
}