#ifndef X86_FB_HEADER
#define X86_FB_HEADER

#include <stdint.h>
#include <stddef.h>

static const size_t FB_WIDTH = 80;
static const size_t FB_HEIGHT = 25;
static const uint16_t FB_COMMAND_PORT = 0x3D4;
static const uint16_t FB_DATA_PORT = 0x3D5;
static const uint8_t FB_HIGH_BYTE_COMMAND = 14;
static const uint8_t FB_LOW_BYTE_COMMAND = 15;

typedef enum fb_color_t_enum {
	FB_COLOR_BLACK = 0,
	FB_COLOR_BLUE = 1,
	FB_COLOR_GREEN = 2,
	FB_COLOR_CYAN = 3,
	FB_COLOR_RED = 4,
	FB_COLOR_MAGENTA = 5,
	FB_COLOR_BROWN = 6,
	FB_COLOR_LIGHT_GREY = 7,
	FB_COLOR_DARK_GREY = 8,
	FB_COLOR_LIGHT_BLUE = 9,
	FB_COLOR_LIGHT_GREEN = 10,
	FB_COLOR_LIGHT_CYAN = 11,
	FB_COLOR_LIGHT_RED = 12,
	FB_COLOR_LIGHT_MAGENTA = 13,
	FB_COLOR_LIGHT_BROWN = 14,
	FB_COLOR_WHITE = 15,
} fb_color_t;
 
void fb_initialize();
void fb_set_color(fb_color_t fg, fb_color_t bg);
void fb_cursor(size_t x, size_t y);
void fb_place_char(char c, fb_color_t color, size_t x, size_t y);
void fb_print_char(char c);
void fb_print_nstring(const char * string, size_t size);
void fb_print_string(const char * string);
void fb_print_uint(uint32_t value);
void fb_print_int(int32_t value);
void fb_print_hex(uint32_t value);
void fb_print_byte(uint8_t value);

#endif
