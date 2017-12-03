#include <library.h>

#include "fb.h"
#include "io.h"
 
u32 fb_row;
u32 fb_column;
fb_color_t fb_color;
u16 * fb_buffer;
 
void fb_set_color(fb_color_t fg, fb_color_t bg) {
	fb_color = fg | bg << 4;
}
 
static inline u16 fb_color_char(unsigned char uc, fb_color_t color) {
	return (u16) uc | (u16) color << 8;
}
 
void fb_initialize(void) {
	fb_row = 0;
	fb_column = 0;
	fb_set_color(FB_COLOR_LIGHT_GREY, FB_COLOR_BLACK);
	fb_buffer = (u16*) 0xB8000;
	for (u32 y = 0; y < FB_HEIGHT; y++) {
		for (u32 x = 0; x < FB_WIDTH; x++) {
			const u32 index = y * FB_WIDTH + x;
			fb_buffer[index] = fb_color_char(' ', fb_color);
		}
	}
    fb_cursor(0, 0);
}
 
void fb_cursor(u32 x, u32 y) {
	const u32 index = y * FB_WIDTH + x;
    out8(FB_COMMAND_PORT, FB_HIGH_BYTE_COMMAND);
    out8(FB_DATA_PORT, ((index >> 8) & 0x00FF));
    out8(FB_COMMAND_PORT, FB_LOW_BYTE_COMMAND);
    out8(FB_DATA_PORT, index & 0x00FF);
}

void fb_place_char(char c, fb_color_t color, u32 x, u32 y) {
	const u32 index = y * FB_WIDTH + x;
	fb_buffer[index] = fb_color_char(c, color);
}

void scroll() {
    for (u32 y = 1; y < FB_HEIGHT; y++) {
		for (u32 x = 0; x < FB_WIDTH; x++) {
			const u32 src = y * FB_WIDTH + x;
			const u32 dest = (y-1) * FB_WIDTH + x;
			fb_buffer[dest] = fb_buffer[src];
		}
    }
    for (u32 x = 0; x < FB_WIDTH; x++) {
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

