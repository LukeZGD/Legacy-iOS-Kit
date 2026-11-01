#include "putc.h"
#include <stddef.h>

static putc_t putc_handler = NULL;

void _putchar(char c) {
    if(putc_handler) {
        putc_handler(c);
    }
}

void add_putc(putc_t handler) {
    putc_handler = handler;
}

