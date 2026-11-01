#ifndef procyon_gadget_finder_h
#define procyon_gadget_finder_h

#include "common.h"

#define JSC_PATH "/System/Library/Frameworks/JavaScriptCore.framework/JavaScriptCore"
#define LIBDYLD_PATH "/usr/lib/system/libdyld.dylib"

uint32_t find_bytes(uint8_t *target, size_t size, bool thumb);
uint32_t find_bytes_in_image(const char *name, uint8_t *target, size_t size, bool thumb);
uint32_t find_pop_r4_r7_pc(void);
uint32_t find_pop_r0_r1_r2_r3_r4_pc(void) ;
uint32_t find_pop_r4_r5_r6_r7_pc(void);
uint32_t find_ldr_r1_r2_4_bx_lr(void);
uint32_t find_ldr_r12_sp_mov_pc_r2(void);
uint32_t find_svc_0x80_bx_lr(void);
uint32_t find_str_r0_r3_bx_lr(void);
uint32_t find_pop_r2_r3_r7_pc(void);
uint32_t find_ldr_r0_r2_bx_lr(void);
uint32_t find_add_r0_r2_bx_lr(void);
uint32_t find_str_r0_r2_bx_lr(void);
uint32_t find_str_r2_r3_bx_lr(void);
uint32_t find_add_r0_r1_bx_lr(void);
uint32_t find_pop_r0_r1_pc(void);
uint32_t find_str_r0_r1_bx_lr(void);
uint32_t find_pop_r12_pc(void);
uint32_t find_pop_lr_pc(void);
uint32_t find_ldm_r1_r3_r5_r10_r11_r12_lr_pc(void);
uint32_t find_ldm_r5_r0_r2_r4_r5_r8_r11_r12_pc(void);
uint32_t find_ldm_r3_r1_r3_r9_r10_pc(void);
uint32_t find_js_proto_lr(void);
uint32_t find_rop_start(void);
uint32_t find_longjmp(void);
uint32_t find_syscall(void);
uint32_t find_mach_msg_trap(void);
uint32_t find_platform_memmove(void);
uint32_t find_platform_memmove_lazy_ptr(void);

#endif /* procyon_gadget_finder_h */
