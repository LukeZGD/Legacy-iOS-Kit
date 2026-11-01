#include "display.h"
#include "font.h"

typedef void(*putc_t)(char c);

void add_putc(putc_t handler);

static uint32_t fb_x = 0;
static uint32_t fb_y = 0;
static uint32_t* framebuffer_address = 0;
static uint32_t display_width = 0;
static uint32_t display_height = 0;
static uint32_t background_colour = 0;
static uint32_t foreground_colour = 0;
static uint32_t scale_factor;


int fb_init(uint32_t* base_address, uint32_t width, uint32_t height) {
	framebuffer_address = base_address;
	display_width = width;
	display_height = height;
	background_colour = COLOUR_BLACK;
	foreground_colour = COLOUR_WHITE;
	scale_factor = 1;
	fb_set_loc(0, 0);
	fb_clear();
	add_putc(&fb_putc);
	return 0;
}

void fb_print_row(char c) {
    uint32_t i;
    
	fb_putc('\n');
	for(i = 0; i < (display_width / (font_width * scale_factor)); i++) {
		fb_putc(c);
	}
	fb_putc('\n');
}

void fb_set_loc(int x, int y) {
	fb_x = x;
	fb_y = y;
}

void fb_clear() {
	uint32_t* p = 0;
	for(p = (uint32_t*)framebuffer_address; p < (uint32_t*)(framebuffer_address + (display_width * display_height)); p++) {
		*p = background_colour;
	}
	fb_set_loc(0, 0);
}

void fb_invert() {
	uint32_t* p = 0;
	for(p = (uint32_t*)framebuffer_address; p < (uint32_t*)(framebuffer_address + (display_width * display_height)); p++) {
		*p = ~ *p;
	}
	background_colour = ~ background_colour;
	foreground_colour = ~ foreground_colour;
}

int font_get_pixel(int ch, int x, int y) {
	return (font[ch & 0x7F][y / scale_factor] & (1 << (x / scale_factor)));
}

volatile uint32_t* fb_get_pixel(register uint32_t x, register uint32_t y) {
	return (((uint32_t*)framebuffer_address) + (y * display_width) + x);
}

static void fb_scrollup() {
	register volatile uint32_t* newFirstLine = fb_get_pixel(0, font_height * scale_factor);
	register volatile uint32_t* oldFirstLine = fb_get_pixel(0, 0);
	register volatile uint32_t* end = oldFirstLine + (display_width * display_height);
	while(newFirstLine < end) {
		*(oldFirstLine++) = *(newFirstLine++);
	}
	while(oldFirstLine < end) {
		*(oldFirstLine++) = background_colour;
	}
	fb_y--;
}

typedef int (*printf_t)(const char *fmt, ...) __attribute__((format(__printf, 1, 2)));
extern printf_t _printf;

void fb_putc(char c) {
	if(!framebuffer_address){
		return;
	}
    
    _printf("%c", c);
    
	if(c == '\r') {
		fb_x = 0;

	} else if(c == '\n') {
		fb_x = 0;
		fb_y++;

	} else {
		register uint32_t sx;
		register uint32_t sy;

		for(sy = 0; sy < (font_height * scale_factor); sy++) {
			for(sx = 0; sx < (font_width * scale_factor); sx++) {
				if(font_get_pixel(c, sx, sy)) {
					*(fb_get_pixel((fb_x * (font_width * scale_factor) + sx), sy + (fb_y * (font_height * scale_factor)))) = foreground_colour;
				} else {
					*(fb_get_pixel((fb_x * (font_width * scale_factor) + sx), sy + (fb_y * (font_height * scale_factor)))) = background_colour;
				}
			}
		}

		fb_x++;
	}

	if(fb_x == (display_width / (font_width * scale_factor))) {
		fb_x = 0;
		fb_y++;
	}

	if(fb_y == (display_height / (font_height * scale_factor))) {
		fb_scrollup();
	}
}

void fb_draw_image(uint32_t* image, uint32_t x, uint32_t y, uint32_t width, uint32_t height) {
	register uint32_t sx;
	register uint32_t sy;
	for(sy = 0; sy < height; sy++) {
		for(sx = 0; sx < width; sx++) {
			*(fb_get_pixel(sx + x, sy + y)) = RGBA2RGB(image[(sy * width) + sx]);
		}
	}
}
