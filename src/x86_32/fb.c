#include <stdint.h>
#include <stddef.h>

#include "fb.h"
#include "io.h"
#include "../string.h"
 
size_t fb_row;
size_t fb_column;
fb_color_t fb_color;
uint16_t * fb_buffer;
 
void fb_set_color(fb_color_t fg, fb_color_t bg) {
	fb_color = fg | bg << 4;
}
 
static inline uint16_t fb_color_char(unsigned char uc, fb_color_t color) {
	return (uint16_t) uc | (uint16_t) color << 8;
}
 
void fb_initialize(void) {
	fb_row = 0;
	fb_column = 0;
	fb_set_color(FB_COLOR_LIGHT_GREY, FB_COLOR_BLACK);
	fb_buffer = (uint16_t*) 0xB8000;
	for (size_t y = 0; y < FB_HEIGHT; y++) {
		for (size_t x = 0; x < FB_WIDTH; x++) {
			const size_t index = y * FB_WIDTH + x;
			fb_buffer[index] = fb_color_char(' ', fb_color);
		}
	}
}
 
void fb_cursor(size_t x, size_t y) {
	const size_t index = y * FB_WIDTH + x;
    out8(FB_COMMAND_PORT, FB_HIGH_BYTE_COMMAND);
    out8(FB_DATA_PORT, ((index >> 8) & 0x00FF));
    out8(FB_COMMAND_PORT, FB_LOW_BYTE_COMMAND);
    out8(FB_DATA_PORT, index & 0x00FF);
}

void fb_place_char(char c, fb_color_t color, size_t x, size_t y) {
	const size_t index = y * FB_WIDTH + x;
	fb_buffer[index] = fb_color_char(c, color);
}

void scroll() {
    for (size_t y = 1; y < FB_HEIGHT; y++) {
		for (size_t x = 0; x < FB_WIDTH; x++) {
			const size_t src = y * FB_WIDTH + x;
			const size_t dest = (y-1) * FB_WIDTH + x;
			fb_buffer[dest] = fb_buffer[src];
		}
    }
    for (size_t x = 0; x < FB_WIDTH; x++) {
        fb_buffer[FB_WIDTH * (FB_HEIGHT-1) + x] = fb_color_char(' ', fb_color);
    }
}
 
void fb_print_char(char c) {
    if (c == '\n') {
        fb_column = 0;
        if (fb_row == (FB_HEIGHT-1)) {
            scroll();
        } else {
            fb_row++;
        }
    } else {
        if (++fb_column == FB_WIDTH) {
            if (fb_row == (FB_HEIGHT-1)) {
                scroll();
            } else {
                fb_row++;
            }
            fb_column = 0;
        }
        fb_place_char(c, fb_color, fb_column, fb_row);
        fb_cursor(fb_column + 1, fb_row);
    }
}
 
void fb_print_nstring(const char * string, size_t size) {
	for (size_t i = 0; i < size; i++) {
		fb_print_char(string[i]);
    }
}
 
void fb_print_string(const char * string) {
	fb_print_nstring(string, strlen(string));
}

void fb_print_int_recurse(uint32_t value) {
    if (value) {
        uint8_t digit = value % 10;
        fb_print_int_recurse(value / 10);
        fb_print_char('0' + digit);
    }
}

void fb_print_uint(uint32_t value) {
    if (!value) {
        fb_print_char('0');
        return;
    }
    fb_print_int_recurse(value);
}

void fb_print_int(int32_t value) {
    if (value < 0) {
        fb_print_char('-');
        value = -value;
    }
    fb_print_uint(value);
}

void fb_print_nibble(uint8_t value) {
    value = value % 16;
    if (value < 10) {
        fb_print_char('0' + value);
    } else {
        fb_print_char('A' + value - 10);
    }
}

void fb_print_hex_recurse(uint32_t value) {
    if (value) {
        fb_print_hex_recurse(value / 16);
        fb_print_nibble(value);
    }
}

void fb_print_hex(uint32_t value) {
    fb_print_char('0');
    fb_print_char('x');
    if (!value) {
        fb_print_char('0');
        return;
    }
    fb_print_hex_recurse(value);
}

void fb_print_byte(uint8_t value) {
    fb_print_nibble(value >> 4);
    fb_print_nibble(value);
}
