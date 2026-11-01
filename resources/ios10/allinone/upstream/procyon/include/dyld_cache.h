#ifndef procyon_dyld_cache_h
#define procyon_dyld_cache_h

#include "common.h"

#define DSC_PATH_ARMV7 "/System/Library/Caches/com.apple.dyld/dyld_shared_cache_armv7"
#define DSC_PATH_ARMV7S "/System/Library/Caches/com.apple.dyld/dyld_shared_cache_armv7s"

typedef struct {
    char magic[16];
    uint32_t mappingOffset;
    uint32_t mappingCount;
    uint32_t imagesOffset;
    uint32_t imagesCount;
    uint64_t dyldBaseAddress;
    uint64_t codeSignatureOffset;
    uint64_t codeSignatureSize;
    uint64_t slideInfoOffsetUnused;
    uint64_t slideInfoSizeUnused;
    uint64_t localSymbolsOffset;
    uint64_t localSymbolsSize;
} dyld_cache_header_t;

typedef struct {
	uint32_t version;
	uint32_t infoArrayCount;
    const struct dyld_image_info *infoArray;
	dyld_image_notifier notification;		
	bool processDetachedFromSharedRegion;
	bool libSystemInitialized;
	const struct mach_header *dyldImageLoadAddress;
	void *jitInfo;
	const char *dyldVersion;
	const char *errorMessage;
	uintptr_t terminationFlags;
	void *coreSymbolicationShmPage;
	uintptr_t systemOrderFlag;
	uintptr_t uuidArrayCount;
	const struct dyld_uuid_info *uuidArray;
	struct dyld_all_image_infos *dyldAllImageInfosAddress;
	uintptr_t initialImageCount;
	uintptr_t errorKind;
	const char *errorClientOfDylibPath;
	const char *errorTargetDylibPath;
	const char *errorSymbol;
	uintptr_t sharedCacheSlide;
	uint8_t sharedCacheUUID[16];
	uintptr_t sharedCacheBaseAddress;
} dyld_all_image_infos_t;

typedef struct {
    uint64_t address;
    uint64_t size;
    uint64_t fileOffset;
    uint32_t maxProt;
    uint32_t initProt;
} dyld_cache_mapping_info_t;

typedef struct {
    uint64_t address;
    uint64_t modTime;
    uint64_t inode;
    uint32_t pathFileOffset;
    uint32_t pad;
} dyld_cache_image_info_t;

typedef struct  {
    uint32_t nlistOffset;
    uint32_t nlistCount;
    uint32_t stringsOffset;
    uint32_t stringsSize;
    uint32_t entriesOffset;
    uint32_t entriesCount;
} dyld_cache_local_symbols_info_t;

typedef struct  {
    uint32_t dylibOffset;
    uint32_t nlistStartIndex;
    uint32_t nlistCount;
} dyld_cache_local_symbols_entry_t;

typedef struct {
    char *path;
    uint32_t virt_addr;
    uintptr_t local_addr;
    uint32_t size;
    uint32_t exec_virt_addr;
    uintptr_t exec_local_addr;
    uint32_t exec_size;
    uint32_t data_virt_addr;
    uintptr_t data_local_addr;
    uint32_t data_size;
    uint32_t start_idx;
    uint32_t end_idx;
} dsc_image_t;

typedef struct {
    uint32_t virt_addr;
    uintptr_t local_addr;
    vm_prot_t init_prot;
    vm_prot_t max_prot;
    uint32_t size;
} dsc_mapping_t;

typedef struct {
    dyld_cache_header_t *hdr;
    bool mapped;
    const char *path;
    size_t size;
    dsc_image_t *images;
    dsc_mapping_t *mappings;
    uint32_t image_count;
    uint32_t mapping_count;
    dyld_cache_local_symbols_info_t *symbol_info;
    dyld_cache_local_symbols_entry_t *symbol_entry;
    struct nlist *symbol_table;
    char *string_table;
    uint32_t slide;
} dsc_info_t;

dsc_info_t *dyld_cache_init(void);
void dyld_cache_deinit(dsc_info_t *dsc_info);
uint32_t dyld_cache_find_symbol(dsc_info_t *dsc_info, const char *path, const char *name);

#endif /* procyon_dyld_cache_h */
