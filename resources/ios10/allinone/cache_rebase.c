/* Apple's slide-info v1/v2 formats:
 * https://github.com/apple-oss-distributions/dyld/blob/main/include/mach-o/dyld_cache_format.h
 * Only words listed by the relocation metadata are decoded. Reading a raw
 * on-disk word as a runtime pointer breaks Procyon's JSC data repairs. */
#include "cache_rebase.h"
#include <string.h>
#include <limits.h>

static int span(uint64_t offset, uint64_t length, uint64_t size) {
    return offset <= size && length <= size - offset;
}
static uint16_t u16(const uint8_t *p) {
    return (uint16_t)p[0] | (uint16_t)p[1] << 8;
}
static uint32_t u32(const uint8_t *p) {
    return (uint32_t)p[0] | (uint32_t)p[1] << 8 |
           (uint32_t)p[2] << 16 | (uint32_t)p[3] << 24;
}
static uint64_t u64(const uint8_t *p) {
    return (uint64_t)u32(p) | (uint64_t)u32(p + 4) << 32;
}

/* Walk an unmodified chain. Delta is in bytes and is always forward. */
static int chain(const uint8_t *page, uint32_t page_size, uint32_t start,
                 uint32_t target, uint32_t mask, unsigned shift,
                 uint32_t add, uint32_t *value, int *is_pointer) {
    uint32_t pos = start;
    for (;;) {
        if ((pos & 3) || !span(pos, 4, page_size)) return -1;
        uint32_t raw = u32(page + pos);
        uint32_t delta = (raw & mask) >> shift;
        if (pos == target) {
            uint32_t decoded = raw & ~mask;
            if (decoded && decoded > UINT32_MAX - add) return -1;
            *is_pointer = decoded != 0;
            *value = decoded ? decoded + add : 0;
            return 1;
        }
        if (!delta) return 0;
        if (delta > page_size - pos) return -1;
        pos += delta;
    }
}

int lik_cache_word(const void *cache, size_t size, uint32_t address,
                   uint32_t *value, int *is_pointer) {
    const uint8_t *b = cache;
    if (!b || !value || !is_pointer || size < 88 || (address & 3) ||
        memcmp(b, "dyld_v1", 7)) return -1;
    uint32_t mo = u32(b + 16), mc = u32(b + 20);
    if (!mc || !span(mo, (uint64_t)mc * 32, size)) return -1;
    uint64_t rw_base = 0, rw_size = 0, rw_file = 0, word_file = 0;
    unsigned found = 0, writable = 0;
    for (uint32_t i = 0; i < mc; ++i) {
        const uint8_t *m = b + mo + (uint64_t)i * 32;
        uint64_t base = u64(m), length = u64(m + 8), file = u64(m + 16);
        if (!span(file, length, size) || base > UINT32_MAX ||
            length > (uint64_t)UINT32_MAX + 1 - base) return -1;
        if (address >= base && span(address - base, 4, length)) {
            word_file = file + address - base;
            ++found;
        }
        if (u32(m + 28) & 2) {
            rw_base = base; rw_size = length; rw_file = file;
            ++writable;
        }
    }
    if (found != 1 || writable != 1) return -1;
    uint32_t raw = u32(b + word_file);
    *value = raw; *is_pointer = 0;
    if (address < rw_base || !span(address - rw_base, 4, rw_size)) return 0;

    uint64_t off = u64(b + 56), length = u64(b + 64);
    if (!off || !span(off, length, size) || length < 4) return -1;
    const uint8_t *info = b + off;
    uint32_t version = u32(info);
    if (version == 1) {
        if (length < 24) return -1;
        uint32_t toc = u32(info + 4), count = u32(info + 8);
        uint32_t entries = u32(info + 12), ec = u32(info + 16);
        uint32_t es = u32(info + 20);
        uint64_t relative = address - rw_base, page = relative / 4096;
        if (es != 128 || page >= count ||
            !span(toc, (uint64_t)count * 2, length) ||
            !span(entries, (uint64_t)ec * es, length)) return -1;
        uint32_t entry = u16(info + toc + page * 2);
        if (entry >= ec) return -1;
        uint32_t bit = (relative % 4096) / 4;
        if (info[entries + (uint64_t)entry * es + bit / 8] & (1u << (bit % 8)))
            *is_pointer = raw != 0;
        return 0;
    }
    if (version != 2 || length < 40) return -1;
    uint32_t ps = u32(info + 4), starts = u32(info + 8), sc = u32(info + 12);
    uint32_t extras = u32(info + 16), ec = u32(info + 20);
    uint64_t mask64 = u64(info + 24), add64 = u64(info + 32);
    if ((ps != 4096 && ps != 16384) || !mask64 || mask64 > UINT32_MAX ||
        add64 > UINT32_MAX || !span(starts, (uint64_t)sc * 2, length) ||
        !span(extras, (uint64_t)ec * 2, length)) return -1;
    uint32_t mask = (uint32_t)mask64, add = (uint32_t)add64;
    unsigned low = 0;
    while (!(mask & (1u << low))) ++low;
    uint32_t bits = mask >> low;
    if (low < 2 || (bits & (bits + 1))) return -1;
    unsigned shift = low - 2;
    uint64_t page_index = (address - rw_base) / ps;
    uint32_t target = (address - rw_base) % ps;
    if (page_index >= sc || !span(page_index * ps, ps, rw_size)) return -1;
    const uint8_t *page = b + rw_file + page_index * ps;
    uint16_t attr = u16(info + starts + page_index * 2);
    if (attr == 0x4000) return 0;
    if (attr & 0x4000) return -1;
    if (!(attr & 0x8000)) {
        int r = chain(page, ps, (uint32_t)attr * 4, target, mask, shift, add,
                      value, is_pointer);
        return r < 0 ? -1 : 0;
    }
    uint32_t index = attr & 0x3fff;
    for (;;) {
        if (index >= ec) return -1;
        uint16_t extra = u16(info + extras + (uint64_t)index++ * 2);
        if (extra & 0x4000) return -1;
        int r = chain(page, ps, (uint32_t)(extra & 0x3fff) * 4, target,
                      mask, shift, add, value, is_pointer);
        if (r < 0) return -1;
        if (r > 0) return 0;
        if (extra & 0x8000) return 0;
    }
}
