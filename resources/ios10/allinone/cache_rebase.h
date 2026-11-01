/* Decode one word from a 32-bit, on-disk dyld cache without modifying it. */
#ifndef LIK_CACHE_REBASE_H
#define LIK_CACHE_REBASE_H
#include <stddef.h>
#include <stdint.h>

/* A pointer result is unslid; stage2 must add the target boot's cache slide.
 * Ordinary data (including nulls carried in a chain) must not be slid.
 * Returns -1 for unsupported or malformed cache metadata. */
int lik_cache_word(const void *cache, size_t size, uint32_t address,
                   uint32_t *value, int *is_pointer);
#endif
