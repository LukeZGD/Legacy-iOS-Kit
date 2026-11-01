#include <stdbool.h>
#include <stdint.h>
#include "printf.h"
#include "putc.h"

#ifndef PRINTF_NTOA_BUFFER_SIZE
#define PRINTF_NTOA_BUFFER_SIZE    32U
#endif

#define FLAGS_ZEROPAD   (1U <<  0U)
#define FLAGS_LEFT      (1U <<  1U)
#define FLAGS_PLUS      (1U <<  2U)
#define FLAGS_SPACE     (1U <<  3U)
#define FLAGS_HASH      (1U <<  4U)
#define FLAGS_UPPERCASE (1U <<  5U)
#define FLAGS_CHAR      (1U <<  6U)
#define FLAGS_SHORT     (1U <<  7U)
#define FLAGS_LONG      (1U <<  8U)
#define FLAGS_LONG_LONG (1U <<  9U)
#define FLAGS_PRECISION (1U << 10U)
#define FLAGS_ADAPT_EXP (1U << 11U)

typedef void (*out_fct_type)(char character, void* buffer, size_t idx, size_t maxlen);

static inline void _out_null(char character, void* buffer, size_t idx, size_t maxlen)
{
    (void)character; (void)buffer; (void)idx; (void)maxlen;
}

static inline void _out_char(char character, void* buffer, size_t idx, size_t maxlen)
{
    (void)buffer; (void)idx; (void)maxlen;
    if (character) {
        _putchar(character);
    }
}

static inline unsigned int _strnlen_s(const char* str, size_t maxsize)
{
    const char* s;
    for (s = str; *s && maxsize--; ++s);
    return (unsigned int)(s - str);
}

static inline bool _is_digit(char ch)
{
    return (ch >= '0') && (ch <= '9');
}

static unsigned int _atoi(const char** str)
{
    unsigned int i = 0U;
    while (_is_digit(**str)) {
        i = i * 10U + (unsigned int)(*((*str)++) - '0');
    }
    return i;
}

static size_t _out_rev(out_fct_type out, char* buffer, size_t idx, size_t maxlen, const char* buf, size_t len, unsigned int width, unsigned int flags)
{
    const size_t start_idx = idx;
    size_t i;
    if (!(flags & FLAGS_LEFT) && !(flags & FLAGS_ZEROPAD)) {
        for (i = len; i < width; i++) {
            out(' ', buffer, idx++, maxlen);
        }
    }
    
    while (len) {
        out(buf[--len], buffer, idx++, maxlen);
    }
    
    if (flags & FLAGS_LEFT) {
        while (idx - start_idx < width) {
            out(' ', buffer, idx++, maxlen);
        }
    }
    
    return idx;
}


static size_t _ntoa_format(out_fct_type out, char* buffer, size_t idx, size_t maxlen, char* buf, size_t len, bool negative, unsigned int base, unsigned int prec, unsigned int width, unsigned int flags)
{
    if (!(flags & FLAGS_LEFT)) {
        if (width && (flags & FLAGS_ZEROPAD) && (negative || (flags & (FLAGS_PLUS | FLAGS_SPACE)))) {
            width--;
        }
        while ((len < prec) && (len < PRINTF_NTOA_BUFFER_SIZE)) {
            buf[len++] = '0';
        }
        while ((flags & FLAGS_ZEROPAD) && (len < width) && (len < PRINTF_NTOA_BUFFER_SIZE)) {
            buf[len++] = '0';
        }
    }
    
    if (flags & FLAGS_HASH) {
        if (!(flags & FLAGS_PRECISION) && len && ((len == prec) || (len == width))) {
            len--;
            if (len && (base == 16U)) {
                len--;
            }
        }
        if ((base == 16U) && !(flags & FLAGS_UPPERCASE) && (len < PRINTF_NTOA_BUFFER_SIZE)) {
            buf[len++] = 'x';
        }
        else if ((base == 16U) && (flags & FLAGS_UPPERCASE) && (len < PRINTF_NTOA_BUFFER_SIZE)) {
            buf[len++] = 'X';
        }
        else if ((base == 2U) && (len < PRINTF_NTOA_BUFFER_SIZE)) {
            buf[len++] = 'b';
        }
        if (len < PRINTF_NTOA_BUFFER_SIZE) {
            buf[len++] = '0';
        }
    }
    
    if (len < PRINTF_NTOA_BUFFER_SIZE) {
        if (negative) {
            buf[len++] = '-';
        }
        else if (flags & FLAGS_PLUS) {
            buf[len++] = '+';
        }
        else if (flags & FLAGS_SPACE) {
            buf[len++] = ' ';
        }
    }
    
    return _out_rev(out, buffer, idx, maxlen, buf, len, width, flags);
}


static char dig(char a, char b){
    char c;
    
    if(a == b){
        return 0;
    }
    
    c = a/b;
    return a - (b*c);
    
}

static size_t _ntoa_long(out_fct_type out, char* buffer, size_t idx, size_t maxlen, unsigned long value, bool negative, unsigned long base, unsigned int prec, unsigned int width, unsigned int flags)
{
    char buf[PRINTF_NTOA_BUFFER_SIZE];
    size_t len = 0U;
    
    if (!value) {
        flags &= ~FLAGS_HASH;
    }
    
    if (!(flags & FLAGS_PRECISION) || value) {
        do {
            /* const char digit = (char)(value % base);
             */
            const char digit = dig(value, base);
            buf[len++] = digit < 10 ? '0' + digit : (flags & FLAGS_UPPERCASE ? 'A' : 'a') + digit - 10;
            value /= base;
        } while (value && (len < PRINTF_NTOA_BUFFER_SIZE));
    }
    
    return _ntoa_format(out, buffer, idx, maxlen, buf, len, negative, (unsigned int)base, prec, width, flags);
}


static int _vsnprintf(out_fct_type out, char* buffer, const size_t maxlen, const char* format, va_list va)
{
    unsigned int flags, width, precision, n;
    size_t idx = 0U;
    
    if (!buffer) {
        out = _out_null;
    }
    
    while (*format)
    {
        if (*format != '%') {
            out(*format, buffer, idx++, maxlen);
            format++;
            continue;
        }
        else {
            format++;
        }
        
        flags = 0U;
        do {
            switch (*format) {
                case '0': flags |= FLAGS_ZEROPAD; format++; n = 1U; break;
                case '-': flags |= FLAGS_LEFT;    format++; n = 1U; break;
                case '+': flags |= FLAGS_PLUS;    format++; n = 1U; break;
                case ' ': flags |= FLAGS_SPACE;   format++; n = 1U; break;
                case '#': flags |= FLAGS_HASH;    format++; n = 1U; break;
                default :                                   n = 0U; break;
            }
        } while (n);
        
        width = 0U;
        if (_is_digit(*format)) {
            width = _atoi(&format);
        }
        else if (*format == '*') {
            const int w = va_arg(va, int);
            if (w < 0) {
                flags |= FLAGS_LEFT;
                width = (unsigned int)-w;
            }
            else {
                width = (unsigned int)w;
            }
            format++;
        }
        
        precision = 0U;
        if (*format == '.') {
            flags |= FLAGS_PRECISION;
            format++;
            if (_is_digit(*format)) {
                precision = _atoi(&format);
            }
            else if (*format == '*') {
                const int prec = (int)va_arg(va, int);
                precision = prec > 0 ? (unsigned int)prec : 0U;
                format++;
            }
        }
        
        switch (*format) {
            case 'l' :
            flags |= FLAGS_LONG;
            format++;
            if (*format == 'l') {
                flags |= FLAGS_LONG_LONG;
                format++;
            }
            break;
            case 'h' :
            flags |= FLAGS_SHORT;
            format++;
            if (*format == 'h') {
                flags |= FLAGS_CHAR;
                format++;
            }
            break;
#if defined(PRINTF_SUPPORT_PTRDIFF_T)
            case 't' :
            flags |= (sizeof(ptrdiff_t) == sizeof(long) ? FLAGS_LONG : FLAGS_LONG_LONG);
            format++;
            break;
#endif
            case 'j' :
            flags |= (sizeof(intmax_t) == sizeof(long) ? FLAGS_LONG : FLAGS_LONG_LONG);
            format++;
            break;
            case 'z' :
            flags |= (sizeof(size_t) == sizeof(long) ? FLAGS_LONG : FLAGS_LONG_LONG);
            format++;
            break;
            default :
            break;
        }
        
        switch (*format) {
            case 'd' :
            case 'i' :
            case 'u' :
            case 'x' :
            case 'X' :
            case 'o' :
            case 'b' : {
                
                unsigned int base;
                if (*format == 'x' || *format == 'X') {
                    base = 16U;
                }
                else if (*format == 'o') {
                    base =  8U;
                }
                else if (*format == 'b') {
                    base =  2U;
                }
                else {
                    base = 10U;
                    flags &= ~FLAGS_HASH;
                }

                if (*format == 'X') {
                    flags |= FLAGS_UPPERCASE;
                }
                
                if ((*format != 'i') && (*format != 'd')) {
                    flags &= ~(FLAGS_PLUS | FLAGS_SPACE);
                }
                
                if (flags & FLAGS_PRECISION) {
                    flags &= ~FLAGS_ZEROPAD;
                }
                
                if ((*format == 'i') || (*format == 'd')) {

                    if (flags & FLAGS_LONG_LONG) {
#if defined(PRINTF_SUPPORT_LONG_LONG)
                        const long long value = va_arg(va, long long);
                        idx = _ntoa_long_long(out, buffer, idx, maxlen, (unsigned long long)(value > 0 ? value : 0 - value), value < 0, base, precision, width, flags);
#endif
                    }
                    else if (flags & FLAGS_LONG) {
                        const long value = va_arg(va, long);
                        idx = _ntoa_long(out, buffer, idx, maxlen, (unsigned long)(value > 0 ? value : 0 - value), value < 0, base, precision, width, flags);
                    }
                    else {
                        const int value = (flags & FLAGS_CHAR) ? (char)va_arg(va, int) : (flags & FLAGS_SHORT) ? (short int)va_arg(va, int) : va_arg(va, int);
                        idx = _ntoa_long(out, buffer, idx, maxlen, (unsigned int)(value > 0 ? value : 0 - value), value < 0, base, precision, width, flags);
                    }
                }
                else {

                    if (flags & FLAGS_LONG_LONG) {
#if defined(PRINTF_SUPPORT_LONG_LONG)
                        idx = _ntoa_long_long(out, buffer, idx, maxlen, va_arg(va, unsigned long long), false, base, precision, width, flags);
#endif
                    }
                    else if (flags & FLAGS_LONG) {
                        idx = _ntoa_long(out, buffer, idx, maxlen, va_arg(va, unsigned long), false, base, precision, width, flags);
                    }
                    else {
                        const unsigned int value = (flags & FLAGS_CHAR) ? (unsigned char)va_arg(va, unsigned int) : (flags & FLAGS_SHORT) ? (unsigned short int)va_arg(va, unsigned int) : va_arg(va, unsigned int);
                        idx = _ntoa_long(out, buffer, idx, maxlen, value, false, base, precision, width, flags);
                    }
                }
                format++;
                break;
            }
#if defined(PRINTF_SUPPORT_FLOAT)
            case 'f' :
            case 'F' :
            if (*format == 'F') flags |= FLAGS_UPPERCASE;
            idx = _ftoa(out, buffer, idx, maxlen, va_arg(va, double), precision, width, flags);
            format++;
            break;
#if defined(PRINTF_SUPPORT_EXPONENTIAL)
            case 'e':
            case 'E':
            case 'g':
            case 'G':
            if ((*format == 'g')||(*format == 'G')) flags |= FLAGS_ADAPT_EXP;
            if ((*format == 'E')||(*format == 'G')) flags |= FLAGS_UPPERCASE;
            idx = _etoa(out, buffer, idx, maxlen, va_arg(va, double), precision, width, flags);
            format++;
            break;
#endif
#endif
            case 'c' : {
                unsigned int l = 1U;
                if (!(flags & FLAGS_LEFT)) {
                    while (l++ < width) {
                        out(' ', buffer, idx++, maxlen);
                    }
                }
                out((char)va_arg(va, int), buffer, idx++, maxlen);
                if (flags & FLAGS_LEFT) {
                    while (l++ < width) {
                        out(' ', buffer, idx++, maxlen);
                    }
                }
                format++;
                break;
            }
            
            case 's' : {
                const char* p = va_arg(va, char*);
                unsigned int l = _strnlen_s(p, precision ? precision : (size_t)-1);
                if (flags & FLAGS_PRECISION) {
                    l = (l < precision ? l : precision);
                }
                if (!(flags & FLAGS_LEFT)) {
                    while (l++ < width) {
                        out(' ', buffer, idx++, maxlen);
                    }
                }
                while ((*p != 0) && (!(flags & FLAGS_PRECISION) || precision--)) {
                    out(*(p++), buffer, idx++, maxlen);
                }
                if (flags & FLAGS_LEFT) {
                    while (l++ < width) {
                        out(' ', buffer, idx++, maxlen);
                    }
                }
                format++;
                break;
            }
            
            case 'p' : {
                width = sizeof(void*) * 2U;
                flags |= FLAGS_ZEROPAD | FLAGS_UPPERCASE;
#if defined(PRINTF_SUPPORT_LONG_LONG)
                const bool is_ll = sizeof(uintptr_t) == sizeof(long long);
                if (is_ll) {
                    idx = _ntoa_long_long(out, buffer, idx, maxlen, (uintptr_t)va_arg(va, void*), false, 16U, precision, width, flags);
                }
                else {
#endif
                    idx = _ntoa_long(out, buffer, idx, maxlen, (unsigned long)((uintptr_t)va_arg(va, void*)), false, 16U, precision, width, flags);
#if defined(PRINTF_SUPPORT_LONG_LONG)
                }
#endif
                format++;
                break;
            }
            
            case '%' :
            out('%', buffer, idx++, maxlen);
            format++;
            break;
            
            default :
            out(*format, buffer, idx++, maxlen);
            format++;
            break;
        }
    }
    
    out((char)0, buffer, idx < maxlen ? idx : maxlen - 1U, maxlen);
    
    return (int)idx;
}


int printf_(const char* format, ...)
{
    va_list va;
    int ret;
    char buffer[1];
    
    va_start(va, format);
    ret = _vsnprintf(_out_char, buffer, (size_t)-1, format, va);
    va_end(va);
    return ret;
}
