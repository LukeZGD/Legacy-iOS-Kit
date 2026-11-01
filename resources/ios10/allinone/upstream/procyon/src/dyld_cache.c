#include "util.h"
#include "procyon.h"
#include "dyld_cache.h"

__attribute__((naked)) static int shared_region_check(void *addr) {
    asm("mov r12, #256");
    asm("add r12, r12, #38");
    asm("svc #0x80");
    asm("bx lr");
}

dsc_info_t *dyld_cache_init(void) {
    const char *path = NULL;
    if (access(DSC_PATH_ARMV7S, F_OK) == 0) {
        path = DSC_PATH_ARMV7S;
    } else {
        path = DSC_PATH_ARMV7;
    }

    bool mapped = true;
    uint32_t size = 0;
    dyld_cache_header_t *hdr = load_file(path, &size);
    if (hdr == NULL) {
        shared_region_check(&hdr);
        if (hdr == NULL) return NULL;
        mapped = false;
    }

    dsc_info_t *dsc_info = calloc(1, sizeof(dsc_info_t));
    dsc_info->images = calloc(1, sizeof(dsc_image_t) * (hdr->imagesCount+1));
    dsc_info->mappings = calloc(1, sizeof(dsc_mapping_t) * (hdr->mappingCount+1));
    dsc_info->image_count = hdr->imagesCount;
    dsc_info->mapping_count = hdr->mappingCount;
    dsc_info->hdr = hdr;
    dsc_info->size = size;
    dsc_info->path = path;
    dsc_info->mapped = mapped;

    task_dyld_info_data_t dyld_info = {0};
    uint32_t count = TASK_DYLD_INFO_COUNT;
    task_info(mach_task_self(), TASK_DYLD_INFO, (task_info_t)&dyld_info, &count);

    dyld_all_image_infos_t *all_image_infos = (dyld_all_image_infos_t *)dyld_info.all_image_info_addr;
    dsc_info->slide = (uint32_t)all_image_infos->sharedCacheSlide;

    if (dsc_info->mapped) {
        dsc_info->symbol_info = (dyld_cache_local_symbols_info_t *)((uint8_t *)dsc_info->hdr + dsc_info->hdr->localSymbolsOffset);
        dsc_info->symbol_entry = (dyld_cache_local_symbols_entry_t *)((uint8_t *)dsc_info->symbol_info + dsc_info->symbol_info->entriesOffset);
        dsc_info->symbol_table = (struct nlist *)((uint8_t *)dsc_info->symbol_info + dsc_info->symbol_info->nlistOffset);
        dsc_info->string_table = (char *)((uint8_t *)dsc_info->symbol_info + dsc_info->symbol_info->stringsOffset);
    }

    dyld_cache_mapping_info_t *mapping_info = (dyld_cache_mapping_info_t *)((uint8_t *)hdr + hdr->mappingOffset);
    for (uint32_t i = 0; i < dsc_info->mapping_count; i++) {
        dsc_info->mappings[i].virt_addr = mapping_info[i].address;
        dsc_info->mappings[i].local_addr = (uintptr_t)hdr + mapping_info[i].fileOffset;
        dsc_info->mappings[i].init_prot = mapping_info[i].initProt;
        dsc_info->mappings[i].max_prot = mapping_info[i].maxProt;
        dsc_info->mappings[i].size = mapping_info[i].size;
    }

    dyld_cache_image_info_t *image_info = (dyld_cache_image_info_t *)((uint8_t *)hdr + hdr->imagesOffset);
    for (uint32_t i = 0; i < dsc_info->image_count; i++) {
        dsc_info->images[i].path = (char *)hdr + image_info[i].pathFileOffset;
        dsc_info->images[i].virt_addr = image_info[i].address;
        dsc_info->images[i].size = image_info[i+1].address - image_info[i].address;
        if (dsc_info->mapped) {
            dsc_info->images[i].start_idx = dsc_info->symbol_entry[i].nlistStartIndex;
            dsc_info->images[i].end_idx = dsc_info->images[i].start_idx + dsc_info->symbol_entry[i].nlistCount;
        }
   
        for (uint32_t j = 0; j < dsc_info->mapping_count; j++) {
            uint32_t min_va = dsc_info->mappings[j].virt_addr;
            uint32_t max_va = min_va + dsc_info->mappings[j].size;

            if (dsc_info->images[i].virt_addr >= min_va && dsc_info->images[i].virt_addr < max_va) {
                uint32_t addr_offset = dsc_info->images[i].virt_addr - min_va;
                dsc_info->images[i].local_addr = dsc_info->mappings[j].local_addr + addr_offset;
                break;
            }
        }

        if (dsc_info->images[i].local_addr == 0) continue;
        struct mach_header *mach_hdr = (struct mach_header *)dsc_info->images[i].local_addr;
        if (mach_hdr->magic != MH_MAGIC && mach_hdr->magic != MH_CIGAM) continue;

        struct load_command *load_cmd = (struct load_command *)(mach_hdr + 1);
        for (uint32_t j = 0; j < mach_hdr->ncmds; j++) {
            if (load_cmd->cmd == LC_SEGMENT) {
                struct segment_command *segment = (struct segment_command *)load_cmd;
                
                if (segment->vmaddr != 0 && segment->vmsize != 0) {
                    if (strcmp(segment->segname, "__TEXT") == 0) {
                        dsc_info->images[i].exec_virt_addr = segment->vmaddr;
                        dsc_info->images[i].exec_local_addr = (uintptr_t)dsc_info->hdr + (segment->vmaddr - procyon->dsc.region_base);
                        dsc_info->images[i].exec_size = segment->vmsize;
                    } else if (strcmp(segment->segname, "__DATA_CONST") == 0) {
                        dsc_info->images[i].data_virt_addr = segment->vmaddr;
                        dsc_info->images[i].data_local_addr = (uintptr_t)dsc_info->hdr + (segment->vmaddr - procyon->dsc.region_base);
                        dsc_info->images[i].data_size = segment->vmsize;
                    }
                }
            }

            if (dsc_info->images[i].exec_virt_addr != 0 && dsc_info->images[i].data_virt_addr != 0) break;
            load_cmd = (struct load_command *)((uint8_t *)load_cmd + load_cmd->cmdsize);
        }
    }
    return dsc_info;
}

void dyld_cache_deinit(dsc_info_t *dsc_info) {
    if (dsc_info == NULL) return;
    if (dsc_info->images != NULL) free(dsc_info->images);
    if (dsc_info->mappings != NULL) free(dsc_info->mappings);
    if (dsc_info->hdr != NULL && dsc_info->mapped) munmap(dsc_info->hdr, dsc_info->size);
    
    bzero(dsc_info, sizeof(dsc_info_t));
    free(dsc_info);
}

static uint32_t dyld_cache_find_exported_symbol(dsc_info_t *dsc_info, dsc_image_t *image, const char *name) {
    struct mach_header *hdr = (struct mach_header *)image->local_addr;
    struct symtab_command *symtab_cmd = NULL;
    struct nlist *symbol_table = NULL;
    char *string_table = NULL;
    uint32_t text_base = 0;

    struct load_command *load_cmd = (struct load_command *)(hdr + 1);
    for (int i = 0; i < hdr->ncmds; i++) {
        if (load_cmd->cmd == LC_SYMTAB) {
            symtab_cmd = (struct symtab_command *)load_cmd;
            break;
        }
        load_cmd = (struct load_command *)((uint8_t *)load_cmd + load_cmd->cmdsize);
    }
    
    if (symtab_cmd == NULL) return 0;
    load_cmd = (struct load_command *)(hdr + 1);

    for (int i = 0; i < hdr->ncmds; i++) {
        if (load_cmd->cmd == LC_SEGMENT) {
            struct segment_command *seg_cmd = (struct segment_command *)load_cmd;

            if (strcmp(seg_cmd->segname, "__TEXT") == 0) {
                if (text_base == 0) text_base = seg_cmd->vmaddr;
            } else if (strcmp(seg_cmd->segname, "__LINKEDIT") == 0) {
                uint32_t symbol_offset = symtab_cmd->symoff - seg_cmd->fileoff;
                uint32_t string_offset = symtab_cmd->stroff - seg_cmd->fileoff;
                
                if (symbol_offset < seg_cmd->filesize) {
                    symbol_table = (struct nlist *)((seg_cmd->vmaddr - image->virt_addr) + image->local_addr + symbol_offset);
                }
                
                if (string_offset < seg_cmd->filesize) {
                    string_table = (char *)((seg_cmd->vmaddr - image->virt_addr) + image->local_addr + string_offset);
                }
            }
        }
    
        if (symbol_table && string_table && text_base) break;
        load_cmd = (struct load_command *)((uint8_t *)load_cmd + load_cmd->cmdsize);
    }

    if (symbol_table == NULL || string_table == NULL) return 0;
    for (int i = 0; i < symtab_cmd->nsyms; i++) {
        uint32_t str_idx = symbol_table[i].n_un.n_strx;
        if (str_idx >= symtab_cmd->strsize || str_idx == 0) continue;
        if ((symbol_table[i].n_type & N_SECT) == 0 || symbol_table[i].n_sect == NO_SECT) continue;

        char *symbol_name = string_table + str_idx;
        if (strcmp(symbol_name, name) == 0) {
            if (symbol_table[i].n_value == 0) continue;
            uint32_t symbol_addr = image->virt_addr - text_base + symbol_table[i].n_value;
            if ((symbol_table[i].n_desc & N_ARM_THUMB_DEF) == N_ARM_THUMB_DEF) symbol_addr |= 0x1;
            return symbol_addr;
        }
    }
    return 0;
}

static uint32_t dyld_cache_find_private_symbol(dsc_info_t *dsc_info, dsc_image_t *image, const char *name) {
    for (uint32_t j = image->start_idx; j < image->end_idx; j++) {
        if (strcmp(name, dsc_info->string_table + dsc_info->symbol_table[j].n_un.n_strx) == 0) {
            uint32_t symbol_addr = dsc_info->symbol_table[j].n_value;
            if ((dsc_info->symbol_table[j].n_desc & N_ARM_THUMB_DEF) == N_ARM_THUMB_DEF) symbol_addr |= 0x1;
            return symbol_addr;
        }
    }
    return 0;
}

uint32_t dyld_cache_find_symbol(dsc_info_t *dsc_info, const char *path, const char *name) {
    uint32_t symbol_addr = 0;
    for (uint32_t i = 0; i < dsc_info->image_count; i++) {
        if (dsc_info->images[i].path == NULL || strcmp(dsc_info->images[i].path, path) != 0) continue;
        if ((symbol_addr = dyld_cache_find_exported_symbol(dsc_info, &dsc_info->images[i], name)) != 0) break;
        if (dsc_info->mapped) {
            if ((symbol_addr = dyld_cache_find_private_symbol(dsc_info, &dsc_info->images[i], name)) != 0) break;
        }
    }
    return symbol_addr;
}
