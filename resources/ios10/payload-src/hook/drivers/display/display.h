#ifndef DISPLAY_H
#define DISPLAY_H

#include <stdint.h>

#define RGB(r, g, b) ((r & 0xFF) << 16) + ((g & 0xFF) << 8) + (b & 0xFF)

#define COLOUR_WHITE RGB(0xFF, 0xFF, 0xFF)
#define COLOUR_BLACK RGB(0, 0, 0)

#define RGBA2RGB(x) ((((x)) & 0xFF) | ((((x) >> 8) & 0xFF) << 8) | ((((x) >> 16) & 0xFF) << 16))

void fb_print_row(char c);
int fb_init(uint32_t* base_address, uint32_t width, uint32_t height);
void fb_set_loc(int x, int y);
void fb_clear();
void fb_invert();
void fb_putc(char c);
void fb_draw_image(uint32_t* image, uint32_t x, uint32_t y, uint32_t width, uint32_t height);
#endif