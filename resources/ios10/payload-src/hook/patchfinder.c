/*
 * patchfinder.c
 * copyright (C) 2021/11/14 sakuRdev
 *
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 */

#include "patchfinder.h"
#include "lib/lib.h"

#define FRAMEBUFFER_SEARCH "framebuffer"
#define GET_ENV_UINT_SEARCH "bootdelay"
#define DISPLAY_TIMING_SEARCH "display-timing"
#define GET_ENV_SEARCH "boot-device"
#define PRINTF_SEARCH "Entering recovery mode, starting command prompt"
/*
#define VERSION_OFFSET 0x280 + 6
*/

/*---- synackuk's atropine ----*/
static void* pattern_search(const void* addr, int len, int pattern, int mask, int step) {
    int i;
    char* caddr = (char*)addr;
    if (len <= 0)
    return NULL;
    if (step < 0) {
        len = -len;
        len &= ~-(step+1);
    } else {
        len &= ~(step-1);
    }
    for (i = 0; i != len; i += step) {
        int x = *(int*)(caddr + i);
        if ((x & mask) == pattern)
        return (void*)(caddr + i);
    }
    return NULL;
}

static void* bl_search_down(const void* start_addr, int len) {
    /* BL pattern is xx Fx xx F8+ */
    return pattern_search(start_addr, len, 0xD000F000, 0xD000F800, 2);
}

static void* ldr_search_up(const void* start_addr, int len) {
    /* LDR pattern is xx xx 48 xx ( 00 00 f8 00 ) */
    return pattern_search(start_addr, len, 0x00004800, 0x0000F800, -2);
}

static void* ldr32_search_up(const void* start_addr, int len) {
    /* LDR32 pattern is DF F8 xx xx */
    return pattern_search(start_addr, len, 0x0000F8DF, 0x0000FFFF, -2);
}

static void* ldr_to(const void* loc) {
    int dw, ldr_target;
    int xref_target = (int)loc;
    int i = xref_target;
    int min_addr = xref_target - 0x420;
    for(; i > min_addr; i -= 2) {
        i = (int)ldr_search_up((void*)i, i - min_addr);
        if (i == 0) {
            return NULL;
        }
        
        dw = *(int*)i;
        ldr_target = ((i + 4) & ~3) + ((dw & 0xff) << 2);
        if (ldr_target == xref_target) {
            return (void*)i;
        }
        i -= 2;
    }
    
    i = xref_target;
    min_addr = xref_target - 0x1000;
    for(; i > min_addr; i -= 4) {
        i = (int)ldr32_search_up((void*)i, i - min_addr);
        if (i == 0) {
            break;
        }
        dw = *(int*)i;
        ldr_target = ((i + 4) & ~3) + ((dw >> 16) & 0xfff);
        if (ldr_target == xref_target) {
            return (void*)i;
        }
    }
    return NULL;
}

static void* resolve_bl32(const void* bl) {
    int jump = 0;
    unsigned short bits = ((unsigned short *)bl)[0];
    unsigned short exts = ((unsigned short *)bl)[1];
    jump |= MASK(bits, 10, 1) << 24;
    jump |= (~(MASK(bits, 10, 1) ^ MASK(exts, 13, 1)) & 0x1) << 23;
    jump |= (~(MASK(bits, 10, 1) ^ MASK(exts, 11, 1)) & 0x1) << 22;
    jump |= MASK(bits, 0, 10) << 12;
    jump |= MASK(exts, 0, 11) << 1;
    jump |= MASK(exts, 12, 1);
    jump <<= 7;
    jump >>= 7;
    return (void*)((int)bl + 4 + jump);
}

void* xref(char* pattern, size_t len) {
    uintptr_t* ref;
    uintptr_t* xref;
    
    ref = memmem(base_address, 0x50000, pattern, len);
    if(!ref) {
        return 0;
    }
    xref = memmem(base_address, 0x50000, &ref, sizeof(ref));
    if(!xref) {
        return 0;
    }
    return xref;
}

static void* last_xref(char* pattern, size_t len) {
    uintptr_t* ref;
    uintptr_t* curr_xref;
    uintptr_t* prev_xref;
    
    ref = memmem(base_address, 0x50000, pattern, len);
    if(!ref) {
        return 0;
    }
    curr_xref = memmem(base_address, 0x50000, &ref, sizeof(ref));
    if(!curr_xref) {
        return 0;
    }
    
    while(curr_xref != 0) {
        prev_xref = curr_xref;
        curr_xref = memmem(curr_xref + 0x4, 0x50000, &ref, sizeof(ref));
    }
    return prev_xref;
}

static void* find_next_LDR_insn_with_string(char* string, size_t len) {
    uintptr_t* ref;
    uintptr_t* ldr;
    
    ref = xref(string, len);
    if(!ref) {
        return 0;
    }
    ldr = ldr_to(ref);
    if(!ldr) {
        return 0;
    }
    return ldr;
}

get_env_t find_get_env() {
    uintptr_t* ldr;
    uintptr_t* bl;
    uintptr_t* ref;
    
    ldr = find_next_LDR_insn_with_string(GET_ENV_SEARCH, strlen(GET_ENV_SEARCH));
    if (!ldr) {
        return 0;
    }
    bl = bl_search_down(ldr, 0x10);
    if (!bl) {
        return 0;
    }
    ref = resolve_bl32(bl);
    if (!ref) {
        return 0;
    }
    return (get_env_t)((uintptr_t)ref);
}

get_env_uint_t find_get_env_uint() {
    uintptr_t* ldr;
    uintptr_t* bl;
    uintptr_t* ref;
    
    
    ldr = find_next_LDR_insn_with_string(GET_ENV_UINT_SEARCH, strlen(GET_ENV_UINT_SEARCH));
    bl = bl_search_down(ldr, 8);
    if (!bl) {
        return 0;
    }
    ref = resolve_bl32(bl);
    if (!ref) {
        return 0;
    }
    return (get_env_uint_t)((uintptr_t)ref);
}

static uintptr_t* find_display_timing_address() {
    static uintptr_t* timing_address;
    char* type;
    
    if(timing_address != 0) {
        return timing_address;
    }
    type = get_env(DISPLAY_TIMING_SEARCH);
    if (!type) {
        return 0;
    }
    timing_address = last_xref(type, strlen(type) + 1);
    if (!timing_address) {
        return 0;
    }
    return timing_address;
}


uintptr_t* find_base_address() {
    return (uintptr_t*)(*(uint32_t*)(0x20) & ~0xFFFFF);
}

uintptr_t* find_framebuffer_address() {
    return (uintptr_t*)get_env_uint(FRAMEBUFFER_SEARCH);
}

uint32_t find_display_width() {
    uintptr_t* width;
    width = (find_display_timing_address() + (sizeof(uint32_t)));
    if(!width) {
        return 0;
    }
    
    return *(uint32_t*)width;
    
}
uint32_t find_display_height() {
    uintptr_t* height;
    height = (find_display_timing_address() + (sizeof(uint32_t) * 0x2));
    if(!height) {
        return 0;
    }
    return *(uint32_t*)height;
}

printf_t find_printf() {
    uintptr_t* ldr;
    uintptr_t* bl;
    uintptr_t* ref;
    
    
    ldr = find_next_LDR_insn_with_string(PRINTF_SEARCH, strlen(PRINTF_SEARCH));
    bl = bl_search_down(ldr, 8);
    if (!bl) {
        return 0;
    }
    ref = resolve_bl32(bl);
    if (!ref) {
        return 0;
    }
    return (printf_t)((uintptr_t)ref);
}

/*
int find_version() {
    return atoi((char *)base_address + VERSION_OFFSET);
}
*/
