#include <stddef.h>

void *memcpy(void *dst, const void *src, size_t len)
{
    const char *s = src;
    char       *d = dst;
    int        pos = 0, dir = 1;
    
    if (d > s) {
        dir = -1;
        pos = len - 1;
    }
    
    while (len--) {
        d[pos] = s[pos];
        pos += dir;
    }
    
    return dst;
}
