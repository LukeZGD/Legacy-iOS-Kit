/*
 * kernel.c
 * copyright (C) 2021/11/14 sakuRdev
 *
 */

#include <stdint.h>
#include "kernel.h"
#include "lib/lib.h"

#ifndef KERNEL_C
#define KERNEL_C
#include "shellcode.h"
#endif

struct kinfo {
    uint32_t addr;
    size_t   size;
};

struct kernel_text {
    struct kinfo base;
    struct kinfo _text;
    struct kinfo _const;
    struct kinfo _cstring;
    struct kinfo _os_log;
};

struct kernel_data {
    struct kinfo base;
};

typedef struct {
    struct kinfo base;
    uint32_t kdumpbase;
    uint32_t kernel_entry;
    struct kernel_text          text;
    struct kernel_data          data;
} kdata_t;

kdata_t kernel_data;

/* --- planetbeing patchfinder --- */
static uint32_t bit_range(uint32_t x, int start, int end)
{
    x = (x << (31 - start)) >> (31 - start);
    x = (x >> end);
    return x;
}

static uint32_t ror(uint32_t x, int places)
{
    return (x >> places) | (x << (32 - places));
}

static int thumb_expand_imm_c(uint16_t imm12)
{
    if(bit_range(imm12, 11, 10) == 0)
    {
        switch(bit_range(imm12, 9, 8))
        {
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
    } else
    {
        uint32_t unrotated_value = 0x80 | bit_range(imm12, 6, 0);
        return ror(unrotated_value, bit_range(imm12, 11, 7));
    }
}

static int insn_is_32bit(uint16_t* i)
{
    return (*i & 0xe000) == 0xe000 && (*i & 0x1800) != 0x0;
}

static uint32_t insn_bl_imm32(uint16_t* i)
{
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

static int insn_is_ldr_literal(uint16_t* i)
{
    return (*i & 0xF800) == 0x4800 || (*i & 0xFF7F) == 0xF85F;
}

static int insn_ldr_literal_rt(uint16_t* i)
{
    if((*i & 0xF800) == 0x4800)
        return (*i >> 8) & 7;
    else if((*i & 0xFF7F) == 0xF85F)
        return (*(i + 1) >> 12) & 0xF;
    else
        return 0;
}

static int insn_ldr_literal_imm(uint16_t* i)
{
    if((*i & 0xF800) == 0x4800)
        return (*i & 0xFF) << 2;
    else if((*i & 0xFF7F) == 0xF85F)
        return (*(i + 1) & 0xFFF) * (((*i & 0x0800) == 0x0800) ? 1 : -1);
    else
        return 0;
}

static int insn_is_add_reg(uint16_t* i)
{
    if((*i & 0xFE00) == 0x1800)
        return 1;
    else if((*i & 0xFF00) == 0x4400)
        return 1;
    else if((*i & 0xFFE0) == 0xEB00)
        return 1;
    else
        return 0;
}

static int insn_add_reg_rd(uint16_t* i)
{
    if((*i & 0xFE00) == 0x1800)
        return (*i & 7);
    else if((*i & 0xFF00) == 0x4400)
        return (*i & 7) | ((*i & 0x80) >> 4) ;
    else if((*i & 0xFFE0) == 0xEB00)
        return (*(i + 1) >> 8) & 0xF;
    else
        return 0;
}

static int insn_add_reg_rn(uint16_t* i)
{
    if((*i & 0xFE00) == 0x1800)
        return ((*i >> 3) & 7);
    else if((*i & 0xFF00) == 0x4400)
        return (*i & 7) | ((*i & 0x80) >> 4) ;
    else if((*i & 0xFFE0) == 0xEB00)
        return (*i & 0xF);
    else
        return 0;
}

static int insn_add_reg_rm(uint16_t* i)
{
    if((*i & 0xFE00) == 0x1800)
        return (*i >> 6) & 7;
    else if((*i & 0xFF00) == 0x4400)
        return (*i >> 3) & 0xF;
    else if((*i & 0xFFE0) == 0xEB00)
        return *(i + 1) & 0xF;
    else
        return 0;
}

static int insn_is_movt(uint16_t* i)
{
    return (*i & 0xFBF0) == 0xF2C0 && (*(i + 1) & 0x8000) == 0;
}

static int insn_movt_rd(uint16_t* i)
{
    return (*(i + 1) >> 8) & 0xF;
}

static int insn_movt_imm(uint16_t* i)
{
    return ((*i & 0xF) << 12) | ((*i & 0x0400) << 1) | ((*(i + 1) & 0x7000) >> 4) | (*(i + 1) & 0xFF);
}

static int insn_is_mov_imm(uint16_t* i)
{
    if((*i & 0xF800) == 0x2000)
        return 1;
    else if((*i & 0xFBEF) == 0xF04F && (*(i + 1) & 0x8000) == 0)
        return 1;
    else if((*i & 0xFBF0) == 0xF240 && (*(i + 1) & 0x8000) == 0)
        return 1;
    else
        return 0;
}

static int insn_mov_imm_rd(uint16_t* i)
{
    if((*i & 0xF800) == 0x2000)
        return (*i >> 8) & 7;
    else if((*i & 0xFBEF) == 0xF04F && (*(i + 1) & 0x8000) == 0)
        return (*(i + 1) >> 8) & 0xF;
    else if((*i & 0xFBF0) == 0xF240 && (*(i + 1) & 0x8000) == 0)
        return (*(i + 1) >> 8) & 0xF;
    else
        return 0;
}

static int insn_mov_imm_imm(uint16_t* i)
{
    if((*i & 0xF800) == 0x2000)
        return *i & 0xF;
    else if((*i & 0xFBEF) == 0xF04F && (*(i + 1) & 0x8000) == 0)
        return thumb_expand_imm_c(((*i & 0x0400) << 1) | ((*(i + 1) & 0x7000) >> 4) | (*(i + 1) & 0xFF));
    else if((*i & 0xFBF0) == 0xF240 && (*(i + 1) & 0x8000) == 0)
        return ((*i & 0xF) << 12) | ((*i & 0x0400) << 1) | ((*(i + 1) & 0x7000) >> 4) | (*(i + 1) & 0xFF);
    else
        return 0;
}

static int insn_is_push(uint16_t* i)
{
    if((*i & 0xFE00) == 0xB400)
        return 1;
    else if(*i == 0xE92D)
        return 1;
    else if(*i == 0xF84D && (*(i + 1) & 0x0FFF) == 0x0D04)
        return 1;
    else
        return 0;
}

static int insn_push_registers(uint16_t* i)
{
    if((*i & 0xFE00) == 0xB400)
        return (*i & 0x00FF) | ((*i & 0x0100) << 6);
    else if(*i == 0xE92D)
        return *(i + 1);
    else if(*i == 0xF84D && (*(i + 1) & 0x0FFF) == 0x0D04)
        return 1 << ((*(i + 1) >> 12) & 0xF);
    else
        return 0;
}

static int insn_is_preamble_push(uint16_t* i)
{
    return insn_is_push(i) && (insn_push_registers(i) & (1 << 14)) != 0;
}

insn_t* find_literal_ref(uint8_t* kdata, size_t ksize, insn_t* insn, uintptr_t address) {
    insn_t* current_instruction = insn;
    uint32_t value[16];
    memset(value, 0, sizeof(value));
    
    while((uintptr_t)current_instruction < (uintptr_t)(kdata + ksize)) {
        if(insn_is_mov_imm(current_instruction)) {
            value[insn_mov_imm_rd(current_instruction)] = insn_mov_imm_imm(current_instruction);
        }
        else if(insn_is_ldr_literal(current_instruction)) {
            uintptr_t literal_address  = (uintptr_t)kdata + ((((uintptr_t)current_instruction - (uintptr_t)kdata) + 4) & 0xFFFFFFFC) + insn_ldr_literal_imm(current_instruction);
            if(literal_address >= (uintptr_t)kdata && (literal_address + 4) <= ((uintptr_t)kdata + ksize)) {
                value[insn_ldr_literal_rt(current_instruction)] = *(uint32_t*)(literal_address);
            }
        }
        else if(insn_is_movt(current_instruction)) {
            value[insn_movt_rd(current_instruction)] |= insn_movt_imm(current_instruction) << 16;
        }
        else if(insn_is_add_reg(current_instruction)) {
            int reg = insn_add_reg_rd(current_instruction);
            if(insn_add_reg_rm(current_instruction) == 15 && insn_add_reg_rn(current_instruction) == reg) {
                value[reg] += ((uintptr_t)current_instruction - (uintptr_t)kdata) + 4;
                if(value[reg] == address) {
                    return current_instruction;
                }
            }
        }
        
        current_instruction += insn_is_32bit(current_instruction) ? 2 : 1;
    }
    
    return NULL;
}

struct segment_command *find_segment(struct mach_header *mh, const char *segname) {
    struct load_command *lc;
    struct segment_command *s, *fs = NULL;
    lc = (struct load_command *)((uintptr_t)mh + sizeof(struct mach_header));
    while ((uintptr_t)lc < (uintptr_t)mh + (uintptr_t)mh->sizeofcmds) {
        if (lc->cmd == LC_SEGMENT) {
            s = (struct segment_command *)lc;
            if (!strcmp(s->segname, segname)) {
                fs = s;
                break;
            }
        }
        lc = (struct load_command *)((uintptr_t)lc + (uintptr_t)lc->cmdsize);
    }
    return fs;
}

/* Find start of a load command in a macho */
struct load_command *find_load_command(struct mach_header *mh, uint32_t cmd)
{
    struct load_command *lc, *flc;
    
    lc = (struct load_command *)((uintptr_t)mh + sizeof(struct mach_header));
    
    while (1) {
        if ((uintptr_t)lc->cmd == cmd) {
            flc = (struct load_command *)(uintptr_t)lc;
            break;
        }
        lc = (struct load_command *)((uintptr_t)lc + (uintptr_t)lc->cmdsize);
    }
    return flc;
}

void* find_sym(struct mach_header *mh, const char *name, uint32_t phys_base, uint32_t virt_base) {
    struct segment_command* linkedit;
    struct symtab_command* symtab;
    uint32_t linkedit_phys;
    char* sym_str_table;
    struct nlist* sym_table;
    uint32_t i;
    
    linkedit = find_segment(mh, SEG_LINKEDIT);
    symtab = (struct symtab_command*) find_load_command(mh, LC_SYMTAB);
    
    linkedit_phys = VIRT_TO_PHYS(linkedit->vmaddr);
    
    sym_str_table = (char*) (((char*)(linkedit_phys - linkedit->fileoff)) + symtab->stroff);
    sym_table = (struct nlist*)(((char*)(linkedit_phys - linkedit->fileoff)) + symtab->symoff);
    
    for (i = 0; i < symtab->nsyms; i++) {
        if (sym_table[i].n_value && !strcmp(name,&sym_str_table[sym_table[i].n_un.n_strx])) {
            return (void*)VIRT_TO_PHYS(sym_table[i].n_value);
        }
    }
    return 0;
}

struct find_search_mask
{
    uint16_t mask;
    uint16_t value;
};

static uint16_t* find_with_search_mask(uint8_t* kdata, uint32_t ksize, int num_masks, const struct find_search_mask* masks)
{
    if(num_masks <= 0 || (uint32_t)num_masks > ksize / sizeof(uint16_t))
        return NULL;
    uint16_t* end = (uint16_t*)(kdata + ksize - (num_masks * sizeof(uint16_t)));
    uint16_t* cur;
    for(cur = (uint16_t*) kdata; cur <= end; ++cur)
    {
        int matched = 1;
        int i;
        for(i = 0; i < num_masks; ++i)
        {
            if((*(cur + i) & masks[i].mask) != masks[i].value)
            {
                matched = 0;
                break;
            }
        }
        
        if(matched)
            return cur;
    }
    
    return NULL;
}

static uint16_t* find_last_insn_matching(uint8_t* kdata, uint16_t* current_instruction, int (*match_func)(uint16_t*))
{
    while((uintptr_t)current_instruction > (uintptr_t)kdata)
    {
        if(insn_is_32bit(current_instruction - 2) && !insn_is_32bit(current_instruction - 3))
        {
            current_instruction -= 2;
        } else
        {
            --current_instruction;
        }
        
        if(match_func(current_instruction))
        {
            return current_instruction;
        }
    }
    
    return NULL;
}

uint32_t find_ret_0_gadget(uint32_t phys_base, uint32_t ksize) {
    uint32_t ret_0_gadget;
    insn_t search[2];
    
    search[0] = MOVS_R0_0;
    search[1] = BX_LR;
    
    ret_0_gadget = (uint32_t)memmem((void*)phys_base, ksize, search, 2 * sizeof(insn_t));
    
    if(!ret_0_gadget) {
        return 0;
    }
    
    ret_0_gadget |= 1;
    return ret_0_gadget;
}

uintptr_t* find_sbops(uintptr_t phys_base, uint32_t ksize) {
    
    uintptr_t seatbelt_sandbox_str_addr;
    char* seatbelt_sandbox_str_xref;
    uint32_t val;
    uintptr_t* sbops_address_loc;
    uintptr_t* sbops_address;
    
    seatbelt_sandbox_str_addr = (uintptr_t)memmem((void*)phys_base, ksize, "Seatbelt sandbox policy", strlen("Seatbelt sandbox policy"));
    
    if(!seatbelt_sandbox_str_addr) {
        return NULL;
    }
    seatbelt_sandbox_str_xref = memmem((void*)phys_base, ksize, &seatbelt_sandbox_str_addr, sizeof(uintptr_t));
    
    if(!seatbelt_sandbox_str_xref) {
        return NULL;
    }
    
    val = 1;
    
    sbops_address_loc = memmem((void*)seatbelt_sandbox_str_xref, 0x10, &val, sizeof(uint32_t));
    
    if(!sbops_address_loc) {
        return NULL;
    }
    sbops_address = (uintptr_t*)*(uintptr_t*)((uintptr_t)sbops_address_loc + 4);
    
    return (uintptr_t*)sbops_address;
}

uint32_t find_PE_i_can_has_debugger(uint32_t phys_base, uint32_t virt_base) {
    uint32_t i;
    
    i = (uint32_t)find_sym((void*)(phys_base+0x1000), "_PE_i_can_has_debugger", phys_base, virt_base);
    if(!i) {
        return 0;
    }
    
    return i;
}

uint32_t find_vfs_context_current(uint32_t phys_base, uint32_t virt_base) {
    uint32_t i;
    
    i = (uint32_t)find_sym((void*)(phys_base+0x1000), "_vfs_context_current", phys_base, virt_base);
    if(!i) {
        return 0;
    }
    
    return i;
}

uint32_t find_vnode_getattr(uint32_t phys_base, uint32_t virt_base) {
    uint32_t i;
    
    i = (uint32_t)find_sym((void*)(phys_base+0x1000), "_vnode_getattr", phys_base, virt_base);
    if(!i) {
        return 0;
    }
    
    return i;
}

uint32_t find_pid_check(uint32_t phys_base, uint32_t ksize)
{
    const struct find_search_mask search_masks[] =
    {
        {0xFFF0, 0xE9C0}, /* strd rx, ry, [sp, #z]              */
        {0x0000, 0x0000}, /*                                    */
        {0xF800, 0x2800}, /* cmp rx, #0                         */
        {0xFF00, 0xD000}, /* beq.n                      <-- NOP */
        {0xF800, 0xF000}, /* bl _port_name_to_task              */
        {0xF800, 0xF800}, /*                                    */
        {0xF800, 0x9000}, /* str rx, [sp, #y]                   */
        {0xF800, 0x2800}  /* cmp rx, #0                         */
        
    };
    
    uint16_t* fn_start = find_with_search_mask((void*)phys_base, ksize, sizeof(search_masks) / sizeof(*search_masks), search_masks);
    
    if(!fn_start) {
        return 0;
    }
    
    return ((uintptr_t)fn_start) + 6;
}

uint32_t find_convert_port_to_locked_task(uint32_t phys_base, uint32_t ksize)
{
    const struct find_search_mask search_masks[] =
    {
        {0xF800, 0x6800}, /* ldr rx, [ry, #z] (y!=sp, z<0x80)   */
        {0xFFF0, 0xF8D0}, /* ldr.w rx, [ry]                     */
        {0x0FFF, 0x0000}, /*                                    */
        {0xFF00, 0x4200}, /* cmp rx, ry (x,y = r0~7)            */
        {0xFF00, 0xD100}, /* bne.n                              */
        {0xFFFF, 0xEE1D}, /* mrc p15, #0, r0, c13, c0, #4       */
        {0xFFFF, 0x0F90}  /*                                    */
    };
    
    uint16_t* fn_start = find_with_search_mask((void*)phys_base, ksize, sizeof(search_masks) / sizeof(*search_masks), search_masks);
    
    if(!fn_start) {
        return 0;
    }
    
    return ((uintptr_t)fn_start) + 8;
}

uint32_t find_mount_103(uint32_t phys_base, uint32_t ksize)
{
    const struct find_search_mask search_masks[] =
    {
        {0xFFF0, 0xF010}, /* tst.w rx, #0x40    */
        {0xFFFF, 0x0F40}, /*                    */
        {0xFF00, 0xD000}, /* beq.n              */
        {0xFFF0, 0xF010}, /* tst.w rx, #0x1     */
        {0xFFFF, 0x0F01}, /*                    */
        {0xFF00, 0xD100}  /* bne.n              */
        
    };
    
    uint16_t* fn_start = find_with_search_mask((void*)phys_base, ksize, sizeof(search_masks) / sizeof(*search_masks), search_masks);
    
    if(!fn_start) {
        return 0;
    }
    
    return ((uintptr_t)fn_start) + 4;
}

uint32_t find_mount_union(uint32_t phys_base, uint32_t ksize)
{
    const struct find_search_mask search_masks[] =
    {
        {0xFF00, 0xD100}, /* bne.n              */
        {0xFFF0, 0xF010}, /* tst.w rx, #0x20    */
        {0xFFFF, 0x0F20}, /*                    */
        {0xFF00, 0xD100}, /* bne.n              */
        {0xF800, 0x9800}, /* ldr rx, [sp, #z]   */
        {0xFFF0, 0xF890}, /* ldrb rx, [ry, #z]  */
        {0x0000, 0x0000}, /*                    */
        {0xFFF0, 0xF010}, /* tst.w rx, #0x1     */
        {0xFFFF, 0x0F01}, /*                    */
        {0xFF00, 0xD000}  /* beq.n              */
    };
    
    uint16_t* fn_start = find_with_search_mask((void*)phys_base, ksize, sizeof(search_masks) / sizeof(*search_masks), search_masks);
    
    if(!fn_start) {
        return 0;
    }
    
    return ((uintptr_t)fn_start) + 2;
}

uint32_t find_vm_map_enter_103(uint32_t phys_base, uint32_t ksize)
{
    const struct find_search_mask search_masks[] =
    {
        {0xFFF0, 0xF010}, /* tst.w rz, #4       */
        {0xFFFF, 0x0F04}, /*                    */
        {0xFF00, 0x4600}, /* mov rx, ry         */
        {0xFFF0, 0xBF10}, /* it ne (?)          */
        {0xFFF0, 0xF020}, /* bic.w rx, ry, #4   */
        {0xF0FF, 0x0004}  /*                    */
    };
    
    uint16_t* fn_start = find_with_search_mask((void*)phys_base, ksize, sizeof(search_masks) / sizeof(*search_masks), search_masks);
    
    if(!fn_start) {
        return 0;
    }
    
    return ((uintptr_t)fn_start) + 8;
}

uint32_t find_vm_map_protect_103(uint32_t phys_base, uint32_t ksize)
{
    const struct find_search_mask search_masks[] =
    {
        {0xFBF0, 0xF010}, /* tst.w rx, #0x20000000  */
        {0x8F00, 0x0F00}, /*                        */
        {0xFF00, 0x4600}, /* mov rx, ry             */
        {0xFFF0, 0xBF00}, /* it eq                  */
        {0xFFF0, 0xF020}, /* bic.w rx, ry, #4       */
        {0xF0FF, 0x0004}, /*                        */
        {0xF800, 0x2800}, /* cmp rx, #0             */
        {0xFFF0, 0xBF00}, /* it eq                  */
        {0xFF00, 0x4600}  /* mov rx, ry             */
        
    };
    
    uint16_t* fn_start = find_with_search_mask((void*)phys_base, ksize, sizeof(search_masks) / sizeof(*search_masks), search_masks);
    
    if(!fn_start) {
        return 0;
    }
    
    return ((uintptr_t)fn_start) + 8;
}

uint32_t find_csops_103(uint32_t phys_base, uint32_t ksize)
{
    const struct find_search_mask search_masks[] =
    {
        {0xFFF0, 0xF8D0}, /* ldr.w rx, [ry, #z] */
        {0x0000, 0x0000}, /*                    */
        {0xFFF0, 0xEA10}, /* tst.w rx, ry       */
        {0xFFF0, 0x0F00}, /*                    */
        {0xFBC0, 0xF000}, /* beq.w              */
        {0xD000, 0x8000}, /*                    */
        {0xF8FF, 0x2000}  /* movs rk, #0        */
    };
    
    uint16_t* fn_start = find_with_search_mask((void*)phys_base, ksize, sizeof(search_masks) / sizeof(*search_masks), search_masks);
    
    if(!fn_start) {
        return 0;
    }
    
    return ((uintptr_t)fn_start) + 8;
}

uint32_t find_vm_fault_enter_103(uint32_t phys_base, uint32_t ksize)
{
    const struct find_search_mask search_masks[] =
    {
        {0xFFF0, 0xF8D0}, /* ldr.w rx, [ry, #z]     */
        {0x0000, 0x0000}, /*                        */
        {0xFFF0, 0xF410}, /* ands rx, ry, #0x100000 */
        {0xF0FF, 0x1080}, /*                        */
        {0xFFF0, 0xF020}, /* bic.w rx, ry, #4       */
        {0xF0FF, 0x0004}, /*                        */
        {0xFF00, 0x4600}  /* mov rx, ry             */
    };
    
    uint16_t* fn_start = find_with_search_mask((void*)phys_base, ksize, sizeof(search_masks) / sizeof(*search_masks), search_masks);
    
    if(!fn_start) {
        return 0;
    }
    
    return (uintptr_t)fn_start;
}

/* modify the cs flags */
uint32_t find_amfi_execve_ret(uint32_t phys_base, uint32_t ksize)
{
    /*
     :: shellcode
     
     _shc:
     b.w _amfi_execve_hook
     ...
     
     _amfi_execve_hook:         @ makes sure amfi doesn't try to kill our binaries
     ldr.w   r0, [sl]           @ cs_flags
     orr     r0, r0, #0x4000000 @ CS_PLATFORM_BINARY
     orr     r0, r0, #0x000f    @ CS_VALID | CS_ADHOC | CS_GET_TASK_ALLOW | CS_INSTALLER
     bic     r0, r0, #0x3f00    @ clearing CS_HARD | CS_KILL | CS_CHECK_EXPIRATION | CS_RESTRICT | CS_ENFORCEMENT | CS_REQUIRE_LV
     str.w   r0, [sl]
     movs    r0, #0x0
     add     sp, #0x18
     pop.w   {r8, sl, fp}
     pop     {r4, r5, r6, r7, pc}
     */
    
    const struct find_search_mask search_masks[] =
    {                       /* :: AMFI.kext                                                     */
        {0xFFFF, 0xF8DA},   /* ldr.w rx, [sl]   <- replace with: b.w _shc @ jump to shellcode   */
        {0x0FFF, 0x0000},   /*                                                                  */
        {0xFFF0, 0xF010},   /* tst.w rx, #8                                                     */
        {0xFFFF, 0x0F08},   /*                                                                  */
        {0xFFF0, 0xBF10},   /* it    ne                                                         */
        {0xFFF0, 0xF440},   /* orr   rx, rx, #0xa00                                             */
        {0xF0FF, 0x6020},   /*                                                                  */
        {0xFFFF, 0xF8CA},   /* str.w rx, [sl]                                                   */
        {0x0FFF, 0x0000},   /*                                                                  */
        {0xF8FF, 0x2000},   /* movs  rk, #0                                                     */
        {0xFF80, 0xB000},   /* add   sp, #x                                                     */
        {0xFFFF, 0xE8BD},   /* pop.w {r8, sl, fp}                                               */
        {0xFFFF, 0x0D00},   /*                                                                  */
        {0xFFFF, 0xBDF0},   /* pop   {r4, r5, r6, r7, pc}                                       */
    };
    
    uint16_t* fn_start = find_with_search_mask((void*)phys_base, ksize, sizeof(search_masks) / sizeof(*search_masks), search_masks);
    
    if(!fn_start) {
        return 0;
    }
    
    return (uintptr_t)fn_start;
    
}

uint32_t find_mapForIO_103(uint32_t phys_base, uint32_t ksize)
{
    const struct find_search_mask search_masks[] =
    {                     /* :: LwVM.kext                       */
        {0xF800, 0x9800}, /* ldr rx, [sp, #z]                   */
        {0xF800, 0x2800}, /* cmp rx, #0                         */
        {0xFF00, 0xD100}, /* bne loc_xxx                        */
        {0xFFF0, 0xF8D0}, /* ldr.w rx, [ry, #z] -> movs r0, #0  */
        {0x0000, 0x0000}, /*                    -> nop          */
        {0xFFF0, 0xF890}, /* ldrb rx, [ry, #z]  -> nop          */
        {0x0000, 0x0000}, /*                    -> nop          */
        {0xFD00, 0xB100}, /* cbz rx, loc_xxx                    */
        {0xF800, 0x9800}  /* ldr rx, [sp, #z]                   */
    };
    
    uint16_t* fn_start = find_with_search_mask((void*)phys_base, ksize, sizeof(search_masks) / sizeof(*search_masks), search_masks);
    
    if(!fn_start) {
        return 0;
    }
    
    return ((uintptr_t)fn_start) + 6;
}

uint32_t find_sandbox_call_i_can_has_debugger_103(uint32_t phys_base, uint32_t ksize)
{
    
    const struct find_search_mask search_masks[] =
    {
        {0xFFFF, 0xB590}, /* PUSH {R4,R7,LR}            */
        {0xFFFF, 0xAF01}, /* ADD  R7, SP, #4            */
        {0xFFFF, 0x2400}, /* MOVS R4, #0                */
        {0xFFFF, 0x2000}, /* MOVS R0, #0                */
        {0xF800, 0xF000}, /* BL   i_can_has_debugger    */
        {0xD000, 0xD000}, /*                            */
        {0xFD07, 0xB100}  /* CBZ  R0, loc_xxx           */
    };
    
    uint16_t* ptr = find_with_search_mask((void*)phys_base, ksize, sizeof(search_masks) / sizeof(*search_masks), search_masks);
    if(!ptr)
        return 0;
    
    return (uintptr_t)ptr + 8;
}

uint32_t find_amfi_cred_label_update_execve(uint32_t phys_base, uint32_t ksize)
{
    uint16_t* ref;
    uint16_t* fn_start;
    uint32_t addr;
    uint16_t* ptr;
    uint8_t* hook_execve;
    const struct find_search_mask search_masks[] =
    {
        {0xFBF0, 0xF010}, /* TST.W Rx, #0x200000    */
        {0x0F00, 0x0F00},
        {0xFF00, 0xD100}  /* BNE x                  */
    };
    
    const char *str = "AMFI: hook..execve() killing pid %u: dyld signature cannot be verified. You either have a corrupt system image or are trying to run an unsigned application outside of a supported development configuration.\n";
    
    hook_execve = memmem((void*)phys_base, ksize, str, strlen(str));
    if(!hook_execve)
        return 0;
    
    ref = find_literal_ref((void*)phys_base, ksize, (uint16_t*) phys_base, (uintptr_t)hook_execve - (uint32_t) phys_base);
    if(!ref)
        return 0;
    
    fn_start = find_last_insn_matching((void*)phys_base, ref, insn_is_preamble_push);
    if(!fn_start)
        return 0;
    
    addr = (uintptr_t)fn_start;
    
    /* fn_start is already an absolute address. Keep the search inside the
     * supplied kernel range instead of adding phys_base a second time. */
    if(addr < phys_base || addr - phys_base >= ksize)
        return 0;
    ptr = find_with_search_mask((void*)addr, ksize - (addr - phys_base), sizeof(search_masks) / sizeof(*search_masks), search_masks);
    if(!ptr)
        return 0;
    
    return (uintptr_t)ptr;
}

uint32_t find_amfi_vnode_check_signature(uint32_t phys_base, uint32_t ksize)
{
    uint8_t* point;
    uint16_t* ref;
    uint16_t* fn_start;
    uint32_t addr;
    uint16_t* ptr;
    
    const struct find_search_mask search_masks[] =
    {
        {0xFF00, 0x4600}, /* mov rx, ry         */
        {0xF800, 0xF000}, /* bl  loc_xxx        */
        {0xD000, 0xD000}, /*                    */
        {0xFF00, 0x4600}, /* mov rx, ry         */
        {0xFD00, 0xB100}, /* cbz rx, loc_xxx    */
        {0xFF00, 0x4600}, /* mov rx, ry         */
        {0xF800, 0xF000}, /* bl  loc_xxx        */
        {0xD000, 0xD000}, /*                    */
        {0xF80F, 0x2801}, /* cmp rx, #1         */
    };
    
    const char *str = "The signature could not be validated because AMFI could not load its entitlements for validation: %s";
    point = memmem((void*)phys_base, ksize, str, strlen(str));
    if(!point)
        return 0;
    
    ref = find_literal_ref((void*)phys_base, ksize, (uint16_t*) phys_base, (uintptr_t)point - (uint32_t) phys_base);
    if(!ref)
        return 0;
    
    fn_start = find_last_insn_matching((void*)phys_base, ref, insn_is_preamble_push);
    if(!fn_start)
        return 0;
    
    addr = (uintptr_t)fn_start;
    
    /* The finder returns an absolute address, not a kernel-relative offset. */
    if(addr < phys_base || addr - phys_base >= ksize)
        return 0;
    ptr = find_with_search_mask((void*)addr, ksize - (addr - phys_base), sizeof(search_masks) / sizeof(*search_masks), search_masks);
    if(!ptr)
        return 0;
    
    return (uintptr_t)ptr;
}

uint32_t find_amfi_loadEntitlementsFromVnode(uint32_t phys_base, uint32_t ksize)
{
    /*
     ldr        r0, =0xXXX  <- this
     add        r0, pc     ; "no code signature"
     */
    
    uint8_t* point;
    uint16_t* ref;
    
    const char *str = "no code signature";
    point = memmem((void*)phys_base, ksize, str, strlen(str));
    if(!point)
        return 0;
    
    ref = find_literal_ref((void*)phys_base, ksize, (uint16_t*) phys_base, (uintptr_t)point - (uint32_t) phys_base);
    if(!ref)
        return 0;
    
    return (uintptr_t)ref - 2;
}

uint32_t find_amfi_vnode_check_exec(uint32_t phys_base, uint32_t ksize)
{
    /*
     push {r4, r7, lr}
     add  r7, sp, #0x4
     ldr  r4, [r7, #x] <- this
     */
    
    uint8_t* point;
    uint16_t* ref;
    uint16_t* fn_start;
    
    const char *str = "csflags";
    
    point = memmem((void*)phys_base, ksize, str, strlen(str));
    if(!point)
        return 0;
    
    ref = find_literal_ref((void*)phys_base, ksize, (uint16_t*) phys_base, (uintptr_t)point - (uint32_t) phys_base);
    if(!ref)
        return 0;
    
    fn_start = find_last_insn_matching((void*)phys_base, ref, insn_is_preamble_push);
    if(!fn_start)
        return 0;
    
    return (uintptr_t)fn_start + 4;
}

uint32_t find_lwvm_i_can_has_krnl_conf_stub(uint32_t phys_base, uint32_t ksize)
{
    uint32_t ret;
    uint32_t imm32;
    uint32_t target;
    uint32_t movw_val;
    uint32_t movt_val;
    uint32_t val;
    uint16_t* fn_start;
    uint16_t* point;
    
    const struct find_search_mask add_ip_pc[] =
    {
        {0xFFFF, 0x44fc} /* add ip, pc */
    };
    
    const struct find_search_mask search_masks[] =
    {
        {0xF80F, 0x2801}, /* cmp rx, #1             */
        {0xFF00, 0xD100}, /* bne.n                  */
        {0xF800, 0xF000}, /* bl  loc_xxx <- this    */
        {0xD000, 0xD000}, /*                        */
        {0xFFF0, 0xF010}, /* tst.w rx, #0x1         */
        {0xFFFF, 0x0F01}, /*                        */
        {0xFF00, 0xD000}, /* beq.n                  */
    };
    
    fn_start = find_with_search_mask((void*)phys_base, ksize, sizeof(search_masks) / sizeof(*search_masks), search_masks);
    
    if(!fn_start) {
        return 0;
    }
    
    fn_start += 2;
    
    imm32 = insn_bl_imm32(fn_start);
    target = ((uintptr_t)fn_start - (uintptr_t)(void*)phys_base) + 4 + imm32;
    
    movw_val = insn_mov_imm_imm((uint16_t*)(void*)(phys_base+target));
    movt_val = insn_movt_imm((uint16_t*)(void*)(phys_base+target+4));
    val = (movt_val << 16) + movw_val;
    
    point = find_with_search_mask((void*)(phys_base+target), ksize, sizeof(add_ip_pc) / sizeof(*add_ip_pc), add_ip_pc);
    if(!point) {
        return 0;
    }
    
    ret = (uintptr_t)point + 4 + val;
    
    return ret;
}

static int kernel_init(uint8_t *buf)
{
    uint32_t min = -1;
    uint32_t max = 0;
    uint32_t i = 0;
    uint32_t j = 0;
    struct section *sec;
    memset(&kernel_data, '\0', sizeof(kdata_t));
    
    if (*(uint32_t*)buf == 0xfeedface) {
        const struct mach_header *hdr = (struct mach_header *)buf;
        const uint8_t *q = (uint8_t*)buf + sizeof(struct mach_header);
        for (i = 0; i < hdr->ncmds; i++) {
            const struct load_command *cmd = (struct load_command *)q;
            if (cmd->cmd == LC_SEGMENT && ((struct segment_command *)q)->vmsize) {
                const struct segment_command *seg = (struct segment_command *)q;
                if (min > seg->vmaddr) {
                    min = seg->vmaddr;
                }
                if (max < seg->vmaddr + seg->vmsize) {
                    max = seg->vmaddr + seg->vmsize;
                }
                
                if (!strcmp(seg->segname, "__TEXT")) {
                    kernel_data.text.base.addr = seg->vmaddr;
                    kernel_data.text.base.size = seg->vmsize;
                    
                    sec = (struct section *)(seg + 1);
                    for (j = 0; j < seg->nsects; j++) {
                        if (!strcmp(sec[j].sectname, "__text")) {
                            kernel_data.text._text.addr = sec[j].addr;
                            kernel_data.text._text.size = sec[j].size;
                        } else if (!strcmp(sec[j].sectname, "__const")) {
                            kernel_data.text._const.addr = sec[j].addr;
                            kernel_data.text._const.size = sec[j].size;
                        } else if (!strcmp(sec[j].sectname, "__cstring")) {
                            kernel_data.text._cstring.addr = sec[j].addr;
                            kernel_data.text._cstring.size = sec[j].size;
                        } else if (!strcmp(sec[j].sectname, "__os_log")) {
                            kernel_data.text._os_log.addr = sec[j].addr;
                            kernel_data.text._os_log.size = sec[j].size;
                        }
                    }
                } else if (!strcmp(seg->segname, "__DATA")) {
                    kernel_data.data.base.addr = seg->vmaddr;
                    kernel_data.data.base.size = seg->vmsize;
                }
            }
            if (cmd->cmd == LC_UNIXTHREAD) {
                uint32_t *ptr = (uint32_t *)(cmd + 1);
                uint32_t flavor = ptr[0];
                struct {
                    uint32_t    r[13];  /* General purpose register r0-r12 */
                    uint32_t    sp;     /* Stack pointer r13 */
                    uint32_t    lr;     /* Link register r14 */
                    uint32_t    pc;     /* Program counter r15 */
                    uint32_t    cpsr;   /* Current program status register */
                } *thread = (typeof(thread))(ptr + 2);
                
                if (flavor == 6) {
                    kernel_data.kernel_entry = thread->pc;
                }
            }
            q = q + cmd->cmdsize;
        }
        
        kernel_data.kdumpbase = min;
        kernel_data.base.size = max - min;
        
        return 0;
    } else {
        return 0;
    }
    
    return 0;
}

uint32_t find_last_text_region(uint32_t phys_base)
{
    uint32_t last_section = 0;
    uint32_t shc_base;
    unsigned int i=0;
    if (kernel_init((void*)(phys_base+0x1000)) == 0){
        uint32_t text_last = kernel_data.text.base.addr + (uint32_t)kernel_data.text.base.size;
        if(kernel_data.data.base.addr == text_last) {
            for (i = 0; i < 4; i++) {
                uint32_t j=0;
                if(i==0) {
                    j = kernel_data.text._text.addr + (uint32_t)kernel_data.text._text.size;
                }
                if(i==1) {
                    j = kernel_data.text._const.addr + (uint32_t)kernel_data.text._const.size;
                }
                if(i==2) {
                    j = kernel_data.text._cstring.addr + (uint32_t)kernel_data.text._cstring.size;
                }
                if(i==3) {
                    j = kernel_data.text._os_log.addr + (uint32_t)kernel_data.text._os_log.size;
                }
                if(j > last_section) last_section = j;
            }
            
            if(text_last <= (last_section+0x100+SHC_LEN)) {
                last_section = 0;
            } else {
                last_section += 0x100;
                last_section = (last_section & ~0xFF);
            }
        } else {
            last_section = 0;
        }
    }
    
    if(last_section != 0) {
        shc_base = last_section;
    } else {
        shc_base = 0;
    }
    
    return shc_base;
}

uint32_t find_prepare_and_jump(uint32_t iboot_base, uint32_t isize){
    uint32_t i;
    uint8_t search[10];
    
    search[0] = 0xf0;
    search[1] = 0xb5;
    search[2] = 0x03;
    search[3] = 0xaf;
    search[4] = 0x15;
    search[5] = 0x46;
    search[6] = 0x0c;
    search[7] = 0x46;
    search[8] = 0x06;
    search[9] = 0x46;
    
    i = (uint32_t)memmem((void*)iboot_base, isize, search, 10 * sizeof(uint8_t));
    if(!i) {
        return 0;
    }
    
    i+=1;
    
    return i;
}

uint32_t find_launchd(uint32_t phys_base, uint32_t ksize) {
    uint32_t str;
    uint8_t search[14];
    
    search[0]  = 0x2f; /* '/' */
    search[1]  = 0x73; /* 's' */
    search[2]  = 0x62; /* 'b' */
    search[3]  = 0x69; /* 'i' */
    search[4]  = 0x6e; /* 'n' */
    search[5]  = 0x2f; /* '/' */
    search[6]  = 0x6c; /* 'l' */
    search[7]  = 0x61; /* 'a' */
    search[8]  = 0x75; /* 'u' */
    search[9]  = 0x6e; /* 'n' */
    search[10] = 0x63; /* 'c' */
    search[11] = 0x68; /* 'h' */
    search[12] = 0x64; /* 'd' */
    search[13] = 0x00; /* '.' */
    
    str = (uint32_t)memmem((void*)phys_base, ksize, search, 14 * sizeof(uint8_t));
    if(!str) {
        return 0;
    }
    
    return str;
}
