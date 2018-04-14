/*
 * Functions for printing to console
 */

/*
 * Platform will define a print_char(char) which will be used by these
 * functions.
 */
#include <platform.h>

/*
 * Print an exact amount of characters in string
 */
void print_nstring(const char * string, u4 size);

/*
 * Print a null terminated string
 */
void print_string(const char * string);

/*
 * Print a unsigned integer
 */
void print_uint(u4 value);

/*
 * Print a signed integer
 */
void print_int(i4 value);

/*
 * Print a signed integer with an optional '+' sign.
 */
void print_int_sign(i4 value, bool show_positive);

/*
 * Print a unsigned integer as a hexadecimal number with a "0x" prefix
 */
void print_hex(u4 value);

/*
 * Print a hexadecimal representation of a byte (no "0x" prefix)
 */
void print_byte(u1 value);

/*
 * printf like functionality with a custom format language:
 *
 * For example, the following code:
 *     const char * city = "West Alton";
 *     i2 change = 24;
 *     print_format("The population of {s} has changed by {+d2}.\n", city, change);
 * Will print:
 *     The population of West Alton has changed by +24.
 *
 * Format expressions are contained in inside curly brackets: {}
 * Two opening brackets "{{" will result in one opening bracket "{", like %%
 * in printf.
 *
 * print_format currently implements these display types:
 *     d
 *         Decimal
 *     x
 *         Hexadecimal
 *     c
 *         Character
 *     s
 *         Null Terminated String
 *
 * Decimal and Hexadecimal must be followed by the size in bytes (1, 2, or 4).
 * If a decimal value is signed, the type must be preceded by + or -.
 * Only "+" will show + if the value is positive, both will show "-" if the
 * value is negative.
 */
void print_format(const char * format, ...);

void print_disable_lock();

