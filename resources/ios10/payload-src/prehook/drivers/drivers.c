#include "drivers.h"

int drivers_init(uint32_t* framebuffer, uint32_t width, uint32_t height) {
	fb_init(framebuffer, width, height);
	return 0;
}
