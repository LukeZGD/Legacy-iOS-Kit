#ifndef procyon_patchfinder_h
#define procyon_patchfinder_h

#include "common.h"

#define IMG3_MAGIC      0x496d6733
#define IMG3_DATA_TYPE  0x44415441

typedef struct {
    uint8_t *input_data;
    uint32_t input_size;
    uint8_t *compressed_data;
    uint32_t compressed_size;
    uint8_t *kernel_data;
    uint32_t kernel_size;
    uint32_t plk_text_addr;
    uint32_t plk_text_size;
    uint32_t plk_text_offset;
    uint32_t kext_offset;
} kcache_t;

typedef struct {
	uint32_t signature;
	uint32_t compression_type;
	uint32_t checksum;
	uint32_t length_uncompressed;
	uint32_t length_compressed;
	uint8_t  padding[0x16C];
	uint8_t  data[0];
} __attribute__((__packed__)) comp_header_t;

int run_patchfinder(void);

#endif /* procyon_patchfinder_h */
