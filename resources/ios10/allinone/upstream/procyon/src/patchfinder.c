#include "procyon.h"
#include "util.h"
#include "patchfinder.h"

static kcache_t *kcache = NULL;

static uint32_t bit_range(uint32_t x, int start, int end) {
    x = (x << (31 - start)) >> (31 - start);
    x = (x >> end);
    return x;
}

static uint32_t ror(uint32_t x, int places) {
    return (x >> places) | (x << (32 - places));
}

static int thumb_expand_imm_c(uint16_t imm12) {
    if(bit_range(imm12, 11, 10) == 0) {
        switch(bit_range(imm12, 9, 8)) {
            case 0:
                return bit_range(imm12, 7, 0);
            case 1:
                return (bit_range(imm12, 7, 0) << 16) | bit_range(imm12, 7, 0);
            case 2:
                return (bit_range(imm12, 7, 0) << 24) | (bit_range(imm12, 7, 0) << 8);
            case 3:
                return (bit_range(imm12, 7, 0) << 24) | (bit_range(imm12, 7, 0) << 16) | (bit_range(imm12, 7, 0) << 8) | bit_range(imm12, 7, 0);
            default:
                return 0;
        }
    } else {
        uint32_t unrotated_value = 0x80 | bit_range(imm12, 6, 0);
        return ror(unrotated_value, bit_range(imm12, 11, 7));
    }
}

static int insn_is_32bit(uint16_t* i) {
    return (*i & 0xe000) == 0xe000 && (*i & 0x1800) != 0x0;
}

static int insn_is_bl(uint16_t* i) {
    if((*i & 0xf800) == 0xf000 && (*(i + 1) & 0xd000) == 0xd000)
        return 1;
    else if((*i & 0xf800) == 0xf000 && (*(i + 1) & 0xd001) == 0xc000)
        return 1;
    else
        return 0;
}

static uint32_t insn_bl_imm32(uint16_t* i) {
    uint16_t insn0 = *i;
    uint16_t insn1 = *(i + 1);
    uint32_t s = (insn0 >> 10) & 1;
    uint32_t j1 = (insn1 >> 13) & 1;
    uint32_t j2 = (insn1 >> 11) & 1;
    uint32_t i1 = ~(j1 ^ s) & 1;
    uint32_t i2 = ~(j2 ^ s) & 1;
    uint32_t imm10 = insn0 & 0x3ff;
    uint32_t imm11 = insn1 & 0x7ff;
    uint32_t imm32 = (imm11 << 1) | (imm10 << 12) | (i2 << 22) | (i1 << 23) | (s ? 0xff000000 : 0);
    return imm32;
}

static int insn_is_b_conditional(uint16_t* i) {
    return (*i & 0xF000) == 0xD000 && (*i & 0x0F00) != 0x0F00 && (*i & 0x0F00) != 0xE;
}

static int insn_is_b_unconditional(uint16_t* i) {
    if((*i & 0xF800) == 0xE000)
        return 1;
    else if((*i & 0xF800) == 0xF000 && (*(i + 1) & 0xD000) == 9)
        return 1;
    else
        return 0;
}

static int insn_is_ldr_literal(uint16_t* i) {
    return (*i & 0xF800) == 0x4800 || (*i & 0xFF7F) == 0xF85F;
}

static int insn_ldr_literal_rt(uint16_t* i) {
    if((*i & 0xF800) == 0x4800)
        return (*i >> 8) & 7;
    else if((*i & 0xFF7F) == 0xF85F)
        return (*(i + 1) >> 12) & 0xF;
    else
        return 0;
}

static int insn_ldr_literal_imm(uint16_t* i) {
    if((*i & 0xF800) == 0x4800)
        return (*i & 0xFF) << 2;
    else if((*i & 0xFF7F) == 0xF85F)
        return (*(i + 1) & 0xFFF) * (((*i & 0x0800) == 0x0800) ? 1 : -1);
    else
        return 0;
}

static int insn_ldr_imm_rt(uint16_t* i) {
    return (*i & 7);
}

static int insn_ldr_imm_rn(uint16_t* i) {
    return ((*i >> 3) & 7);
}

static int insn_ldr_imm_imm(uint16_t* i) {
    return ((*i >> 6) & 0x1F);
}


static int insn_ldrb_imm_rt(uint16_t* i) {
    return (*i & 7);
}

int insn_ldr_reg_rt(uint16_t* i) {
    if((*i & 0xFE00) == 0x5800)
        return *i & 0x7;
    else if((*i & 0xFFF0) == 0xF850 && (*(i + 1) & 0x0FC0) == 0x0000)
        return (*(i + 1) >> 12) & 0xF;
    else
        return 0;
}

int insn_ldr_reg_rm(uint16_t* i) {
    if((*i & 0xFE00) == 0x5800)
        return (*i >> 6) & 0x7;
    else if((*i & 0xFFF0) == 0xF850 && (*(i + 1) & 0x0FC0) == 0x0000)
        return *(i + 1) & 0xF;
    else
        return 0;
}

static int insn_is_add_reg(uint16_t* i) {
    if((*i & 0xFE00) == 0x1800)
        return 1;
    else if((*i & 0xFF00) == 0x4400)
        return 1;
    else if((*i & 0xFFE0) == 0xEB00)
        return 1;
    else
        return 0;
}

static int insn_add_reg_rd(uint16_t* i) {
    if((*i & 0xFE00) == 0x1800)
        return (*i & 7);
    else if((*i & 0xFF00) == 0x4400)
        return (*i & 7) | ((*i & 0x80) >> 4) ;
    else if((*i & 0xFFE0) == 0xEB00)
        return (*(i + 1) >> 8) & 0xF;
    else
        return 0;
}

static int insn_add_reg_rn(uint16_t* i) {
    if((*i & 0xFE00) == 0x1800)
        return ((*i >> 3) & 7);
    else if((*i & 0xFF00) == 0x4400)
        return (*i & 7) | ((*i & 0x80) >> 4) ;
    else if((*i & 0xFFE0) == 0xEB00)
        return (*i & 0xF);
    else
        return 0;
}

static int insn_add_reg_rm(uint16_t* i) {
    if((*i & 0xFE00) == 0x1800)
        return (*i >> 6) & 7;
    else if((*i & 0xFF00) == 0x4400)
        return (*i >> 3) & 0xF;
    else if((*i & 0xFFE0) == 0xEB00)
        return *(i + 1) & 0xF;
    else
        return 0;
}

static int insn_is_movt(uint16_t* i) {
    return (*i & 0xFBF0) == 0xF2C0 && (*(i + 1) & 0x8000) == 0;
}

static int insn_movt_rd(uint16_t* i) {
    return (*(i + 1) >> 8) & 0xF;
}

static int insn_movt_imm(uint16_t* i) {
    return ((*i & 0xF) << 12) | ((*i & 0x0400) << 1) | ((*(i + 1) & 0x7000) >> 4) | (*(i + 1) & 0xFF);
}

static int insn_is_mov_imm(uint16_t* i) {
    if((*i & 0xF800) == 0x2000)
        return 1;
    else if((*i & 0xFBEF) == 0xF04F && (*(i + 1) & 0x8000) == 0)
        return 1;
    else if((*i & 0xFBF0) == 0xF240 && (*(i + 1) & 0x8000) == 0)
        return 1;
    else
        return 0;
}

static int insn_mov_imm_rd(uint16_t* i) {
    if((*i & 0xF800) == 0x2000)
        return (*i >> 8) & 7;
    else if((*i & 0xFBEF) == 0xF04F && (*(i + 1) & 0x8000) == 0)
        return (*(i + 1) >> 8) & 0xF;
    else if((*i & 0xFBF0) == 0xF240 && (*(i + 1) & 0x8000) == 0)
        return (*(i + 1) >> 8) & 0xF;
    else
        return 0;
}

static int insn_mov_imm_imm(uint16_t* i) {
    if((*i & 0xF800) == 0x2000)
        return *i & 0xF;
    else if((*i & 0xFBEF) == 0xF04F && (*(i + 1) & 0x8000) == 0)
        return thumb_expand_imm_c(((*i & 0x0400) << 1) | ((*(i + 1) & 0x7000) >> 4) | (*(i + 1) & 0xFF));
    else if((*i & 0xFBF0) == 0xF240 && (*(i + 1) & 0x8000) == 0)
        return ((*i & 0xF) << 12) | ((*i & 0x0400) << 1) | ((*(i + 1) & 0x7000) >> 4) | (*(i + 1) & 0xFF);
    else
        return 0;
}

static int insn_is_push(uint16_t* i) {
    if((*i & 0xFE00) == 0xB400)
        return 1;
    else if(*i == 0xE92D)
        return 1;
    else if(*i == 0xF84D && (*(i + 1) & 0x0FFF) == 0x0D04)
        return 1;
    else
        return 0;
}

static int insn_push_registers(uint16_t* i) {
    if((*i & 0xFE00) == 0xB400)
        return (*i & 0x00FF) | ((*i & 0x0100) << 6);
    else if(*i == 0xE92D)
        return *(i + 1);
    else if(*i == 0xF84D && (*(i + 1) & 0x0FFF) == 0x0D04)
        return 1 << ((*(i + 1) >> 12) & 0xF);
    else
        return 0;
}

static int insn_is_preamble_push(uint16_t* i) {
    return insn_is_push(i) && (insn_push_registers(i) & (1 << 14)) != 0;
}

static uint16_t* find_last_insn_matching(uint32_t region, uint8_t* kdata, size_t ksize, uint16_t* current_instruction, int (*match_func)(uint16_t*)) {
    while((uintptr_t)current_instruction > (uintptr_t)kdata) {
        if(insn_is_32bit(current_instruction - 2) && !insn_is_32bit(current_instruction - 3)) {
            current_instruction -= 2;
        } else {--current_instruction;}
        if(match_func(current_instruction)) {return current_instruction;}
    }
    return NULL;
}

static uint32_t find_pc_rel_value(uint32_t region, uint8_t* kdata, size_t ksize, uint16_t* insn, int reg) {
    int found = 0;
    uint16_t* current_instruction = insn;
    while((uintptr_t)current_instruction > (uintptr_t)kdata) {
        if(insn_is_32bit(current_instruction - 2)) { current_instruction -= 2;
        } else { --current_instruction; }

        if(insn_is_mov_imm(current_instruction) && insn_mov_imm_rd(current_instruction) == reg) {found = 1;break;}
        if(insn_is_ldr_literal(current_instruction) && insn_ldr_literal_rt(current_instruction) == reg) {found = 1;break;}
    }

    if(!found) return 0;
    uint32_t value = 0;
    while((uintptr_t)current_instruction < (uintptr_t)insn) {
        if(insn_is_mov_imm(current_instruction) && insn_mov_imm_rd(current_instruction) == reg) {
            value = insn_mov_imm_imm(current_instruction);
        } else if(insn_is_ldr_literal(current_instruction) && insn_ldr_literal_rt(current_instruction) == reg) {
            value = *(uint32_t*)(kdata + (((((uintptr_t)current_instruction - (uintptr_t)kdata) + 4) & 0xFFFFFFFC) + insn_ldr_literal_imm(current_instruction)));
        } else if(insn_is_movt(current_instruction) && insn_movt_rd(current_instruction) == reg) {
            value |= insn_movt_imm(current_instruction) << 16;
        } else if(insn_is_add_reg(current_instruction) && insn_add_reg_rd(current_instruction) == reg) {
            if(insn_add_reg_rm(current_instruction) != 15 || insn_add_reg_rn(current_instruction) != reg) {return 0;}
            value += ((uintptr_t)current_instruction - (uintptr_t)kdata) + 4;
        }
        current_instruction += insn_is_32bit(current_instruction) ? 2 : 1;
    }
    return value;
}

static uint16_t* find_literal_ref(uint32_t region, uint8_t* kdata, size_t ksize, uint16_t* insn, uint32_t address) {
    uint16_t* current_instruction = insn;
    uint32_t value[16] = {0};
    memset(value, 0, sizeof(value));

    while((uintptr_t)current_instruction < (uintptr_t)(kdata + ksize)) {
        if(insn_is_mov_imm(current_instruction)) {
            value[insn_mov_imm_rd(current_instruction)] = insn_mov_imm_imm(current_instruction);
        } else if(insn_is_ldr_literal(current_instruction)) {
            uintptr_t literal_address  = (uintptr_t)kdata + ((((uintptr_t)current_instruction - (uintptr_t)kdata) + 4) & 0xFFFFFFFC) + insn_ldr_literal_imm(current_instruction);
            if(literal_address >= (uintptr_t)kdata && (literal_address + 4) <= ((uintptr_t)kdata + ksize)) {
                value[insn_ldr_literal_rt(current_instruction)] = *(uint32_t*)(literal_address);
            }
        } else if(insn_is_movt(current_instruction)) {
            int reg = insn_movt_rd(current_instruction);
            value[reg] |= insn_movt_imm(current_instruction) << 16;
            if(value[reg] == address) {return current_instruction;}
        } else if(insn_is_add_reg(current_instruction)) {
            int reg = insn_add_reg_rd(current_instruction);
            if(insn_add_reg_rm(current_instruction) == 15 && insn_add_reg_rn(current_instruction) == reg) {
                value[reg] += ((uintptr_t)current_instruction - (uintptr_t)kdata) + 4;
                if(value[reg] == address) {return current_instruction;}
            }
        }
        current_instruction += insn_is_32bit(current_instruction) ? 2 : 1;
    }
    return NULL;
}

struct find_search_mask {
    uint16_t mask;
    uint16_t value;
};

static uint16_t* find_with_search_mask(uint32_t region, uint8_t* kdata, size_t ksize, int num_masks, const struct find_search_mask* masks) {
    uint16_t* end = (uint16_t*)(kdata + ksize - (num_masks * sizeof(uint16_t)));
    uint16_t* cur;
    for(cur = (uint16_t*) kdata; cur <= end; ++cur) {
        int matched = 1;
        int i;
        for(i = 0; i < num_masks; ++i) {
            if((*(cur + i) & masks[i].mask) != masks[i].value) {matched = 0;break;}
        }
        if(matched) return cur;
    }
    return NULL;
}

static uint32_t find_mov_r0_1_bx_lr(uint32_t region, uint8_t* kdata, size_t ksize) {
    const uint8_t search[] = {0x01, 0x20, 0x70, 0x47};
    void* ptr = memmem(kdata, ksize, search, sizeof(search)) + 1;
    if(!ptr) return 0;
    return ((uintptr_t)ptr) - ((uintptr_t)kdata);
}

static uint32_t find_proc_enforce(uint32_t region, uint8_t* kdata, size_t ksize) {
    uint8_t* proc_enforce_description = memmem(kdata, ksize, "Enforce MAC policy on process operations", sizeof("Enforce MAC policy on process operations"));
    if(!proc_enforce_description) return 0;

    uint32_t proc_enforce_description_address = region + ((uintptr_t)proc_enforce_description - (uintptr_t)kdata);
    uint8_t* proc_enforce_description_ptr = memmem(kdata, ksize, &proc_enforce_description_address, sizeof(proc_enforce_description_address));
    if(!proc_enforce_description_ptr) return 0;

    uint32_t* proc_enforce_ptr = (uint32_t*)(proc_enforce_description_ptr - (5 * sizeof(uint32_t)));
    return *proc_enforce_ptr - region;
}

static uint32_t find_i_can_has_debugger_2(uint32_t region, uint8_t* kdata, size_t ksize) {
    const struct find_search_mask search_masks[] = {
        {0xFD07, 0xB101},  // CBZ  R1, loc_xxx
        {0xFBF0, 0xF240},
        {0x8F00, 0x0100},
        {0xFBF0, 0xF2C0},
        {0xFF00, 0x0100},
        {0xFFFF, 0x4479},
        {0xF807, 0x6801},  // LDR  R1, [Ry,#X]
        {0xFF00, 0xE000}   // B  x
    };
    
    uint16_t* insn = find_with_search_mask(region, kdata, ksize, sizeof(search_masks) / sizeof(*search_masks), search_masks);
    if(!insn) return 0;
    insn += 5;
    
    uint32_t value = find_pc_rel_value(region, kdata, ksize, insn, insn_ldrb_imm_rt(insn));
    if(!value) return 0;
    value +=4;
    return value + ((uintptr_t)insn) - ((uintptr_t)kdata);
}

static uint32_t find_pid_check(uint32_t region, uint8_t* kdata, size_t ksize) {
    const struct find_search_mask search_masks[] = {
        {0xFFF0, 0xE9C0}, // strd rx, ry, [sp, #z]
        {0x0000, 0x0000},
        {0xF800, 0x2800}, // cmp rx, #0
        {0xFF00, 0xD000}, // beq.n
        {0xF800, 0xF000}, // bl _port_name_to_task
        {0xF800, 0xF800},
        {0xF800, 0x9000}, // str rx, [sp, #y]
        {0xF800, 0x2800}  // cmp rx, #0
    };
    
    uint16_t* fn_start = find_with_search_mask(region, kdata, ksize, sizeof(search_masks) / sizeof(*search_masks), search_masks);
    if(!fn_start) return 0;
    return ((uintptr_t)fn_start) + 6 - ((uintptr_t)kdata);
}

static uint32_t find_convert_port_to_locked_task(uint32_t region, uint8_t* kdata, size_t ksize) {
    const struct find_search_mask search_masks[] = {
        {0xF800, 0x6800}, // ldr rx, [ry, #z] (y!=sp, z<0x80)
        {0xFFF0, 0xF8D0}, // ldr.w rx, [ry]
        {0x0FFF, 0x0000},
        {0xFF00, 0x4200}, // cmp rx, ry (x,y = r0~7)
        {0xFF00, 0xD100}, // bne.n
        {0xFFFF, 0xEE1D}, // mrc p15, #0, r0, c13, c0, #4
        {0xFFFF, 0x0F90}
    };
    
    uint16_t* fn_start = find_with_search_mask(region, kdata, ksize, sizeof(search_masks) / sizeof(*search_masks), search_masks);
    if(!fn_start) return 0;
    return ((uintptr_t)fn_start) + 8 - ((uintptr_t)kdata);
}

static uint32_t find_mount_patch(uint32_t region, uint8_t* kdata, size_t ksize) {
    const struct find_search_mask search_masks[] = {
        {0xFFF0, 0xF010}, // tst.w rx, #0x40
        {0xFFFF, 0x0F40},
        {0xFF00, 0xD000}, // beq.n
        {0xFFF0, 0xF010}, // tst.w rx, #0x1
        {0xFFFF, 0x0F01},
        {0xFF00, 0xD100}  // bne.n
    };
    
    uint16_t* fn_start = find_with_search_mask(region, kdata, ksize, sizeof(search_masks) / sizeof(*search_masks), search_masks);
    if(!fn_start) return 0;
    return ((uintptr_t)fn_start) + 4 - ((uintptr_t)kdata);
}

static uint32_t find_vm_map_enter(uint32_t region, uint8_t* kdata, size_t ksize) {
    const struct find_search_mask search_masks[] = {
        {0xFFF0, 0xF010}, // tst.w rz, #4
        {0xFFFF, 0x0F04},
        {0xFF00, 0x4600}, // mov rx, ry
        {0xFFF0, 0xBF10}, // it ne (?)
        {0xFFF0, 0xF020}, // bic.w rx, ry, #4
        {0xF0FF, 0x0004}
    };
    
    uint16_t* fn_start = find_with_search_mask(region, kdata, ksize, sizeof(search_masks) / sizeof(*search_masks), search_masks);
    if(!fn_start) return 0;
    return ((uintptr_t)fn_start) + 8 - ((uintptr_t)kdata);
}

static uint32_t find_vm_map_protect(uint32_t region, uint8_t* kdata, size_t ksize) {
    const struct find_search_mask search_masks[] = {
        {0xFBF0, 0xF010}, // tst.w rx, #0x20000000
        {0x8F00, 0x0F00},
        {0xFF00, 0x4600}, // mov rx, ry
        {0xFFF0, 0xBF00}, // it eq
        {0xFFF0, 0xF020}, // bic.w rx, ry, #4
        {0xF0FF, 0x0004},
        {0xF800, 0x2800}, // cmp rx, #0
        {0xFFF0, 0xBF00}, // it eq
        {0xFF00, 0x4600}  // mov rx, ry
    };
    
    uint16_t* fn_start = find_with_search_mask(region, kdata, ksize, sizeof(search_masks) / sizeof(*search_masks), search_masks);
    if(!fn_start) return 0;
    return ((uintptr_t)fn_start) + 8 - ((uintptr_t)kdata);
}

static uint32_t find_csops(uint32_t region, uint8_t* kdata, size_t ksize) {
    const struct find_search_mask search_masks[] = {
        {0xFFF0, 0xF8D0}, // ldr.w rx, [ry, #z]
        {0x0000, 0x0000},
        {0xFFF0, 0xEA10}, // tst.w rx, ry
        {0xFFF0, 0x0F00},
        {0xFBC0, 0xF000}, // beq.w
        {0xD000, 0x8000},
        {0xF8FF, 0x2000}  // movs rk, #0
    };
    
    uint16_t *loc = find_with_search_mask(region, kdata, ksize, sizeof(search_masks) / sizeof(*search_masks), search_masks);
    if (loc != NULL) return ((uintptr_t)loc) + 8 - ((uintptr_t)kdata);
    const struct find_search_mask search_masks_alt[] = {
        {0xFFF0, 0xF8D0}, // ldr.w rx, [ry, #z]
        {0x0000, 0x0000},
        {0xff00, 0x4200}, // tst rx, ry
        {0xf000, 0xd000}, // beq ...
        {0xF8FF, 0x2000}, // movs rd, #0
        {0xFFF0, 0xE9C0}, // strd rx, ry, [sp, #z]
        {0x0000, 0x0000},
        {0xFFF0, 0xF8D0}, // ldr.w rx, [ry, #z]
        {0x0000, 0x0000},
    };
    
    loc = find_with_search_mask(region, kdata, ksize, sizeof(search_masks_alt) / sizeof(*search_masks_alt), search_masks_alt);
    if (loc != NULL) return ((uintptr_t)loc) + 6 - ((uintptr_t)kdata);
    return 0;
}

static uint32_t find_vm_fault_enter(uint32_t region, uint8_t* kdata, size_t ksize) {
    const struct find_search_mask search_masks[] = {
        {0xFFF0, 0xF8D0}, // ldr.w rx, [ry, #z]
        {0x0000, 0x0000},
        {0xFFF0, 0xF410}, // ands rx, ry, #0x100000
        {0xF0FF, 0x1080},
        {0xFFF0, 0xF020}, // bic.w rx, ry, #4
        {0xF0FF, 0x0004},
        {0xFF00, 0x4600}  // mov rx, ry
    };
    
    uint16_t *loc = find_with_search_mask(region, kdata, ksize, sizeof(search_masks) / sizeof(*search_masks), search_masks);
    if (loc != NULL) return ((uintptr_t)loc) + 0 - ((uintptr_t)kdata);
    
    const struct find_search_mask search_masks_alt[] = {
        {0xFFF0, 0xF8D0}, // ldr.w rx, [ry, #z]
        {0x0000, 0x0000},
        {0xFFF0, 0xF410}, // ands rx, ry, #0x100000
        {0xF0FF, 0x1080},
        {0xFFF0, 0xF020}, // bic.w rx, ry, #4
        {0xF0FF, 0x0004},
        {0xF800, 0x9000}, // str rx, [sp, #y]
    };
    
    loc = find_with_search_mask(region, kdata, ksize, sizeof(search_masks_alt) / sizeof(*search_masks_alt), search_masks_alt);
    if (loc != NULL) return ((uintptr_t)loc) + 0 - ((uintptr_t)kdata);
    return 0;
}

static uint32_t find_mapForIO(uint32_t region, uint8_t* kdata, size_t ksize) {
    const struct find_search_mask search_masks[] = {
        {0xF800, 0x9800}, // ldr rx, [sp, #z]
        {0xF800, 0x2800}, // cmp rx, #0
        {0xFF00, 0xD100}, // bne loc_xxx
        {0xFFF0, 0xF8D0}, // ldr.w rx, [ry, #z] -> movs r0, #0
        {0x0000, 0x0000}, //                    -> nop
        {0xFFF0, 0xF890}, // ldrb rx, [ry, #z]  -> nop
        {0x0000, 0x0000}, //                    -> nop
        {0xFD00, 0xB100}, // cbz rx, loc_xxx
        {0xF800, 0x9800}  // ldr rx, [sp, #z]
    };
    
    uint16_t* fn_start = find_with_search_mask(region, kdata, ksize, sizeof(search_masks) / sizeof(*search_masks), search_masks);
    if(!fn_start) return 0;
    return ((uintptr_t)fn_start) + 6 - ((uintptr_t)kdata);
}

static uint32_t find_sandbox_call_i_can_has_debugger(uint32_t region, uint8_t* kdata, size_t ksize) {
    const struct find_search_mask search_masks[] = {
        {0xFFFF, 0xB590}, // PUSH {R4,R7,LR}
        {0xFFFF, 0xAF01}, // ADD  R7, SP, #4
        {0xFFFF, 0x2400}, // MOVS R4, #0
        {0xFFFF, 0x2000}, // MOVS R0, #0
        {0xF800, 0xF000}, // BL   i_can_has_debugger
        {0xD000, 0xD000},
        {0xFD07, 0xB100}  // CBZ  R0, loc_xxx
    };
    
    uint16_t* ptr = find_with_search_mask(region, kdata, ksize, sizeof(search_masks) / sizeof(*search_masks), search_masks);
    if(!ptr) return 0;
    return (uintptr_t)ptr + 8 - ((uintptr_t)kdata);
}

static uint32_t find_i_can_has_debugger_1(uint32_t region, uint8_t* kdata, size_t ksize) {
    const struct find_search_mask search_masks[] = {
        {0xFD07, 0xB100},  // CBZ  R0, loc_xxx
        {0xFBF0, 0xF240},
        {0x8F00, 0x0100},
        {0xFBF0, 0xF2C0},
        {0xFF00, 0x0100},
        {0xFFFF, 0x4479},
        {0xF807, 0x6801},  // LDR  R1, [Ry,#X]
        {0xFD07, 0xB101},  // CBZ  R1, loc_xxx
        {0xFBF0, 0xF240},
        {0x8F00, 0x0100},
    };
    
    uint16_t* insn = find_with_search_mask(region, kdata, ksize, sizeof(search_masks) / sizeof(*search_masks), search_masks);
    if(!insn) return 0;
    insn += 5;
    uint32_t value = find_pc_rel_value(region, kdata, ksize, insn, insn_ldrb_imm_rt(insn));
    if(!value) return 0;
    value +=4;
    return value + ((uintptr_t)insn) - ((uintptr_t)kdata);
}

static uint32_t find_amfi_cred_label_update_execve(uint32_t region, uint8_t* kdata, size_t ksize) {
    const char *str = "AMFI: hook..execve() killing pid %u: dyld signature cannot be verified. You either have a corrupt system image or are trying to run an unsigned application outside of a supported development configuration.\n";
    uint8_t* hook_execve = memmem(kdata, ksize, str, strlen(str));
    if(!hook_execve) return 0;
    
    uint16_t* ref = find_literal_ref(region, kdata, ksize, (uint16_t*) kdata, (uintptr_t)hook_execve - (uintptr_t)kdata);
    if(!ref) return 0;
    
    uint16_t* fn_start = find_last_insn_matching(region, kdata, ksize, ref, insn_is_preamble_push);
    if(!fn_start) return 0;
    uint32_t addr = (uintptr_t)fn_start - ((uintptr_t)kdata);
    
    const struct find_search_mask search_masks[] = {
        {0xFBF0, 0xF010}, // TST.W Rx, #0x200000
        {0x0F00, 0x0F00},
        {0xFF00, 0xD100}  // BNE x
    };
    
    uint16_t* ptr = find_with_search_mask(region, kdata+addr, ksize, sizeof(search_masks) / sizeof(*search_masks), search_masks);
    if(!ptr) return 0;
    return (uintptr_t)ptr - ((uintptr_t)kdata);
}

static uint32_t find_amfi_vnode_check_signature(uint32_t region, uint8_t* kdata, size_t ksize) {
    const char *str = "The signature could not be validated because AMFI could not load its entitlements for validation: %s";
    uint8_t* point = memmem(kdata, ksize, str, strlen(str));
    if(!point) return 1;
    
    uint16_t* ref = find_literal_ref(region, kdata, ksize, (uint16_t*) kdata, (uintptr_t)point - (uintptr_t)kdata);
    if(!ref) return 2;
    uint16_t* fn_start = find_last_insn_matching(region, kdata, ksize, ref, insn_is_preamble_push);
    if(!fn_start) return 3;
    uint32_t addr = (uintptr_t)fn_start - ((uintptr_t)kdata);
    
    const struct find_search_mask search_masks[] = {
        {0xFF00, 0x4600}, // mov rx, ry
        {0xF800, 0xF000}, // bl  loc_xxx
        {0xD000, 0xD000},
        {0xFF00, 0x4600}, // mov rx, ry
        {0xFD00, 0xB100}, // cbz rx, loc_xxx
        {0xFF00, 0x4600}, // mov rx, ry
        {0xF800, 0xF000}, // bl  loc_xxx
        {0xD000, 0xD000},
        {0xF80F, 0x2801}, // cmp rx, #1
    };
    
    uint16_t* ptr = find_with_search_mask(region, kdata+addr, ksize, sizeof(search_masks) / sizeof(*search_masks), search_masks);
    if(!ptr) return 4;
    return (uintptr_t)ptr - ((uintptr_t)kdata);
}

static uint32_t find_amfi_loadEntitlementsFromVnode(uint32_t region, uint8_t* kdata, size_t ksize) {
    const char *str = "no code signature";
    uint8_t* point = memmem(kdata, ksize, str, strlen(str));
    if(!point) return 0;
    
    uint16_t* ref = find_literal_ref(region, kdata, ksize, (uint16_t*) kdata, (uintptr_t)point - (uintptr_t)kdata);
    if(!ref) return 0;
    return (uintptr_t)ref - 0x2 - ((uintptr_t)kdata);
}

static uint32_t find_amfi_vnode_check_exec(uint32_t region, uint8_t* kdata, size_t ksize) {
    const char *str = "csflags";
    uint8_t *point = memmem(kdata, ksize, str, strlen(str));
    if (point != NULL) {
        uint16_t *ref = find_literal_ref(region, kdata, ksize, (uint16_t*) kdata, (uintptr_t)point - (uintptr_t)kdata);
        if (ref != NULL) {
            uint16_t *fn_start = find_last_insn_matching(region, kdata, ksize, ref, insn_is_preamble_push);
            if (fn_start != NULL) return (uintptr_t)fn_start + 4 - ((uintptr_t)kdata);
        }
    }

    const struct find_search_mask search_masks[] = {
        {0xFFFF, 0x697C},
        {0xFFFF, 0xB12C},
        {0xFFFF, 0x6820},
        {0xFFFF, 0xF440},
        {0xFFFF, 0x7040},
        {0xFFFF, 0x6020},
    };
    
    uint16_t *loc = find_with_search_mask(region, kdata, ksize, sizeof(search_masks) / sizeof(*search_masks), search_masks);
    if (loc != NULL) return (uintptr_t)loc - ((uintptr_t)kdata);
   
    return 0;
}

static uint32_t find_lwvm_i_can_has_krnl_conf_stub(uint32_t region, uint8_t* kdata, size_t ksize) {
    const struct find_search_mask search_masks[] = {
        {0xF80F, 0x2801}, // cmp rx, #1
        {0xFF00, 0xD100}, // bne.n
        {0xF800, 0xF000}, // bl  loc_xxx <- this
        {0xD000, 0xD000},
        {0xFFF0, 0xF010}, // tst.w rx, #0x1
        {0xFFFF, 0x0F01},
        {0xFF00, 0xD000}, // beq.n
    };
    
    uint16_t* fn_start = find_with_search_mask(region, kdata, ksize, sizeof(search_masks) / sizeof(*search_masks), search_masks);
    if(!fn_start) return 0;
    fn_start += 2;
    uint32_t imm32 = insn_bl_imm32(fn_start);
    uint32_t target = ((uintptr_t)fn_start - (uintptr_t)kdata) + 4 + imm32;
    uint32_t movw_val = insn_mov_imm_imm((uint16_t *)((uintptr_t)kdata+target));
    uint32_t movt_val = insn_movt_imm((uint16_t *)((uintptr_t)kdata+target+4));
    uint32_t val = (movt_val << 16) + movw_val;
    
    const struct find_search_mask add_ip_pc[] = {{0xFFFF, 0x44fc}};
    uint16_t* point = find_with_search_mask(region, kdata+target, ksize, sizeof(add_ip_pc) / sizeof(*add_ip_pc), add_ip_pc);
    if(!point) return 0;
    uint32_t ret = ((uintptr_t)point - (uintptr_t)kdata) + 4 + val;
    return ret;
}

static uint32_t find_vfs_context_current(uint32_t region, uint8_t* kdata, size_t ksize) {
    const struct find_search_mask search_masks[] = {
        {0xFF80, 0xB080}, // sub sp, x
        {0xFFFF, 0xEE1D}, // mrc p15, #0x0, r0, c13, c0, #0x4
        {0xFFFF, 0x0F90}, //
        {0xFFF0, 0xF8D0}, // ldr.w rx, [ry, #z]
        {0x0000, 0x0000},
        {0xF800, 0x9000}, // str rx, [sp, #y]
    };
    
    uint16_t* ptr = find_with_search_mask(region, kdata, ksize, sizeof(search_masks) / sizeof(*search_masks), search_masks);
    if(!ptr) return 0;
    return (uintptr_t)ptr - ((uintptr_t)kdata);
}

static uint32_t find_vnode_getattr(uint32_t region, uint8_t* kdata, size_t ksize) {
    const struct find_search_mask search_masks[] = {
        {0xFFC0, 0x6800}, // ldr rx, [ry]
        {0xFFF0, 0xF410}, // tst.w rx, #0x800
        {0xFFFF, 0x6F00},
        {0xFF00, 0xD000}, // beq
        {0xFFF0, 0xF010}, // tst.w rx, #0x4000000
        {0xFFFF, 0x6F80},
        {0xFF00, 0xD000}, // beq
        {0xFFC0, 0x6800}, // ldr rx, [ry]
        {0xFFF0, 0xF010}, // tst.w rx, #0x4000000
        {0xFFFF, 0x6F80},
        {0xFF00, 0xD000}  // beq
    };
    
    uint16_t* ptr = find_with_search_mask(region, kdata, ksize, sizeof(search_masks) / sizeof(*search_masks), search_masks);
    if(!ptr) return 0;
    uint16_t* fn_start = find_last_insn_matching(region, kdata, ksize, ptr, insn_is_preamble_push);
    if(!fn_start) return 0;
    return (uintptr_t)fn_start - ((uintptr_t)kdata);
}

static uint32_t find_sbops(uint32_t region, uint8_t* kdata, size_t ksize) {
    uintptr_t sbPolicyFullName = (uintptr_t)memmem(kdata, ksize, "Seatbelt sandbox policy", strlen("Seatbelt sandbox policy"));
    sbPolicyFullName -= (uintptr_t)kdata;

    uint32_t search[1];
    search[0] = sbPolicyFullName + region + kcache->kext_offset;

    uintptr_t policyConf_mpcName = (uintptr_t)memmem(kdata, ksize, &search, 4);
    if (policyConf_mpcName == 0) return 0;
    policyConf_mpcName -= ((uintptr_t)kdata + 4);

    uint32_t sb_mpcOps = *(uint32_t*)(kdata + (policyConf_mpcName + 0x10));
    uint32_t sbops = sb_mpcOps - region - kcache->kext_offset;
    return sbops;
}

static uint32_t find_sb_disable(uint32_t region, uint8_t* kdata, size_t ksize) {
    const struct find_search_mask search_mask[] = {
        {0xFFF0, 0xE9C0},
        {0x0000, 0x0000},
        {0xF800, 0x9800},
        {0xF800, 0x2800},
        {0xF800, 0x9800},
        {0xFBC0, 0xF000},
        {0xD000, 0x8000}
    };
    
    uint16_t *ptr = find_with_search_mask(region, kdata, ksize, sizeof(search_mask) / sizeof(*search_mask), search_mask);
    if (ptr != NULL) return (uintptr_t)ptr - ((uintptr_t)kdata) + 0xa;

    const struct find_search_mask search_mask_alt[] = {
        {0xF800, 0x9800}, // ldr rx, [sp, #z]
        {0xF800, 0x2800}, // cmp r0, #0
        {0xff00, 0xd000}, // beq ...
        {0xffff, 0x4625}, // mov r5, r4
        {0xF800, 0x9800}, // ldr rx, [sp, #z]
    };

    ptr = find_with_search_mask(region, kdata, ksize, sizeof(search_mask_alt) / sizeof(*search_mask_alt), search_mask_alt);
    if (ptr != NULL) return (uintptr_t)ptr - ((uintptr_t)kdata) + 0x4;
    return 0;
}

static uint32_t find_cs_system_require_lv(uint32_t region, uint8_t* kdata, size_t ksize) {
    const struct find_search_mask search_mask[] = {
        {0xFFFF, 0x2001}, // MOVS R0, #1
        {0xFFFF, 0x4770}, // BX LR
        {0xFFFF, 0x68C2}, // LDR R2, [R0,#0xC]
        {0xFFFF, 0x6901}, // LDR R1, [R0,#0x10]
        {0xFFFF, 0x4610}, // MOV R0, R2
        {0xFFFF, 0x4770}, // BX LR
    };
    
    uint16_t *ptr = find_with_search_mask(region, kdata, ksize, sizeof(search_mask) / sizeof(*search_mask), search_mask);
    if (ptr == NULL) return 0;
    return (uintptr_t)ptr - ((uintptr_t)kdata);
}

static uint32_t find_amfi_cs_flags_patch(uint32_t region, uint8_t* kdata, size_t ksize) {
    const struct find_search_mask search_mask[] = {
        {0xFFF0, 0xF010}, // tst.w r?, #8
        {0xFFFF, 0x0F08},
        {0xFFFF, 0xBF1C}, // itt ne
        {0xFFF0, 0xF440}, // orrne.w r0, r?, #0x800000
        {0xFFFF, 0x0000},
        {0xFFFF, 0xF8CA}, // strne.w R0, [R10]
        {0xFFFF, 0x0000},
        {0xFFFF, 0xF04F}, // mov.w R0, #0
        {0xFFFF, 0x0000}
    };
    
    uint16_t *ptr = find_with_search_mask(region, kdata, ksize, sizeof(search_mask) / sizeof(*search_mask), search_mask);
    if (ptr == NULL) return 0;
    return (uintptr_t)ptr - ((uintptr_t)kdata);
}

static int lzss_decompress(uint8_t *dst, uint8_t *src, uint32_t srclen) {
    uint8_t text_buf[4113] = {0};
    uint8_t *dststart = dst;
    uint8_t *srcend = src + srclen;
    int i, j, k, r, c;
    unsigned int flags;

    dst = dststart;
    srcend = src + srclen;
    for (i = 0; i < 4078; i++)
        text_buf[i] = ' ';

    r = 4078;
    flags = 0;
    for ( ; ; ) {
        if (((flags >>= 1) & 0x100) == 0) {
            if (src < srcend) c = *src++; else break;
            flags = c | 0xFF00;
        }

        if (flags & 1) {
            if (src < srcend) c = *src++; else break;
            *dst++ = c;
            text_buf[r++] = c;
            r &= (4096 - 1);
        } else {
            if (src < srcend) i = *src++; else break;
            if (src < srcend) j = *src++; else break;
            i |= ((j & 0xF0) << 4);
            j  =  (j & 0x0F) + 2;
            for (k = 0; k <= j; k++) {
                c = text_buf[(i + k) & (4096 - 1)];
                *dst++ = c;
                text_buf[r++] = c;
                r &= (4096 - 1);
            }
        }
    }
    return dst - dststart;
}

static void kcache_close(kcache_t *kcache) {
    if (kcache == NULL) return;
    if (kcache->input_data != MAP_FAILED && kcache->input_data != NULL) {
        munmap(kcache->input_data, kcache->input_size);
    }

    if (kcache->kernel_data != NULL) free(kcache->kernel_data);
    free(kcache);
}

static kcache_t *kcache_open(const char *path) {
    if (path == NULL) return NULL;
    kcache_t *kcache = NULL;
    struct stat st = {0};
    int fd = -1;
    int status = -1;

    if ((fd = open(path, O_RDONLY)) < 0) goto done;    
    if (fstat(fd, &st) != 0 || st.st_size <= 0) goto done;

    if ((kcache = calloc(1, sizeof(kcache_t))) == NULL) goto done;
    if ((kcache->input_data = mmap(NULL, st.st_size, PROT_READ, MAP_PRIVATE, fd, 0)) == MAP_FAILED) goto done;
    kcache->input_size = (uint32_t)st.st_size;

    if (kcache->input_size < 0x1000 || *(uint32_t *)kcache->input_data != IMG3_MAGIC) goto done;
    for (uint32_t i = 0; i < 0x400; i+=0x4) {
        if (*(uint32_t *)(kcache->input_data + i) == IMG3_DATA_TYPE) {
            kcache->compressed_data = kcache->input_data + i + 0xc;
            kcache->compressed_size = *(uint32_t *)(kcache->input_data + i + 0x8);
            break;
        }
    }

    if (kcache->compressed_data == NULL || kcache->compressed_size < 0x1000) goto done;
    comp_header_t *comp_hdr = (comp_header_t *)kcache->compressed_data;
    uint8_t *comp_data = (uint8_t *)(kcache->compressed_data + sizeof(comp_header_t));
    
    if ((kcache->kernel_data = calloc(1, OSSwapHostToBigInt32(comp_hdr->length_uncompressed))) == NULL) goto done;
    kcache->kernel_size = OSSwapHostToBigInt32(comp_hdr->length_uncompressed);

    lzss_decompress(kcache->kernel_data, comp_data, OSSwapHostToBigInt32(comp_hdr->length_compressed));
    munmap(kcache->input_data, kcache->input_size);
    kcache->compressed_data = NULL;
    kcache->input_data = NULL;

    struct mach_header *hdr = (struct mach_header *)kcache->kernel_data;
    struct load_command *load_cmd = (struct load_command *)(hdr + 1);

    for (uint32_t i = 0; i < hdr->ncmds; i++) {
        if (load_cmd->cmd == LC_SEGMENT) {
            struct segment_command *segment = (struct segment_command *)load_cmd;
			struct section *section = (struct section *)(segment + 1);

            if (strcmp(segment->segname, "__PRELINK_TEXT") == 0) {
                for (uint32_t j = 0; j < segment->nsects; j++) {
                    if (strcmp(section[j].sectname, "__text") == 0) {
                        kcache->plk_text_addr = section[j].addr;
                        kcache->plk_text_size = section[j].size;
                        kcache->plk_text_offset = section[j].offset;
                    }
                }
                break;
            }
        }
        load_cmd = (struct load_command *)((uintptr_t)load_cmd + load_cmd->cmdsize);
    }

    if (kcache->plk_text_addr == 0) goto done;
    kcache->kext_offset = (kcache->plk_text_addr - kcache->plk_text_offset) - 0x80001000;
    status = 0;

done:
    if (fd >= 0) close(fd);
    if (status == 0) return kcache;

    kcache_close(kcache);
    return NULL;
}

static uint32_t find_patch_offset(uint32_t (*func)(uint32_t, uint8_t *, size_t), bool is_kext) {
    uint32_t addr = func(0x80001000, kcache->kernel_data, kcache->kernel_size);
    if (addr <= 0xffff) return 0;
    if (is_kext) addr += kcache->kext_offset;

    if ((addr & 0x80000000) == 0x80000000) return addr;
    return addr + 0x80001000;
}

int run_patchfinder(void) {
    kcache = NULL;
    int status = -1;

    if ((kcache = kcache_open("/System/Library/Caches/com.apple.kernelcaches/kernelcache")) == NULL) goto done;
    if ((procyon->offsets.kernel.proc_enforce = find_patch_offset(find_proc_enforce, false)) == 0) goto done;
    if ((procyon->offsets.kernel.ret1_gadget = find_patch_offset(find_mov_r0_1_bx_lr, false)) == 0) goto done;
    if ((procyon->offsets.kernel.pid_check = find_patch_offset(find_pid_check, false)) == 0) goto done;
    if ((procyon->offsets.kernel.i_can_has_debugger_1 = find_patch_offset(find_i_can_has_debugger_1, false)) == 0) goto done;
    if ((procyon->offsets.kernel.i_can_has_debugger_2 = find_patch_offset(find_i_can_has_debugger_2, false)) == 0) goto done;
    if ((procyon->offsets.kernel.mount_patch = find_patch_offset(find_mount_patch, false)) == 0) goto done;
    if ((procyon->offsets.kernel.vm_map_enter = find_patch_offset(find_vm_map_enter, false)) == 0) goto done;
    if ((procyon->offsets.kernel.vm_map_protect = find_patch_offset(find_vm_map_protect, false)) == 0) goto done;
    if ((procyon->offsets.kernel.vm_fault_enter = find_patch_offset(find_vm_fault_enter, false)) == 0) goto done;
    if ((procyon->offsets.kernel.csops_patch = find_patch_offset(find_csops, false)) == 0) goto done;
    if ((procyon->offsets.kernel.amfi_cred_label_update_execve = find_patch_offset(find_amfi_cred_label_update_execve, true)) == 0) goto done;
    if ((procyon->offsets.kernel.amfi_vnode_check_signature = find_patch_offset(find_amfi_vnode_check_signature, true)) == 0) goto done;
    if ((procyon->offsets.kernel.amfi_loadEntitlementsFromVnode = find_patch_offset(find_amfi_loadEntitlementsFromVnode, true)) == 0) goto done;
    if ((procyon->offsets.kernel.amfi_vnode_check_exec = find_patch_offset(find_amfi_vnode_check_exec, true)) == 0) goto done;
    if ((procyon->offsets.kernel.amfi_cs_flags_patch = find_patch_offset(find_amfi_cs_flags_patch, true)) == 0) goto done;
    if ((procyon->offsets.kernel.mapForIO = find_patch_offset(find_mapForIO, true)) == 0) goto done;
    if ((procyon->offsets.kernel.sbcall_debugger = find_patch_offset(find_sandbox_call_i_can_has_debugger, true)) == 0) goto done;
    if ((procyon->offsets.kernel.vfsContextCurrent = find_patch_offset(find_vfs_context_current, false)) == 0) goto done;
    if ((procyon->offsets.kernel.vnodeGetattr = find_patch_offset(find_vnode_getattr, false)) == 0) goto done;
    if ((procyon->offsets.kernel.kernelConfig_stub = find_patch_offset(find_lwvm_i_can_has_krnl_conf_stub, true)) == 0) goto done;
    if ((procyon->offsets.kernel.sb_ops = find_patch_offset(find_sbops, true)) == 0) goto done;
    if ((procyon->offsets.kernel.cs_system_require_lv = find_patch_offset(find_cs_system_require_lv, false)) == 0) goto done;

    if (procyon->ios_version[1] == 3) {
        if ((procyon->offsets.kernel.locked_task = find_patch_offset(find_convert_port_to_locked_task, false)) == 0) goto done;
        if ((procyon->offsets.kernel.sb_disable = find_patch_offset(find_sb_disable, true)) == 0) goto done;

        uint32_t offset = ((procyon->offsets.kernel.sb_disable - kcache->kext_offset) - 0x80001000);
        uint16_t inst = *(uint16_t *)(kcache->kernel_data + offset + 0x2);
        procyon->offsets.kernel.sb_disable_size = (inst == 0x4625) ? 0x2 : 0x4;
    }
    
    uint32_t offset = (procyon->offsets.kernel.csops_patch - 0x80001000);
    uint16_t inst = *(uint16_t *)(kcache->kernel_data + offset + 0x2);
    procyon->offsets.kernel.csops_patch_size = ((inst & 0xF8FF) == 0x2000) ? 0x4 : 0x6;
    status = 0;

done:
    kcache_close(kcache);
    kcache = NULL;
    return status;
}
