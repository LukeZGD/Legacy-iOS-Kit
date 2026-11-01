#ifndef procyon_h
#define procyon_h

#include "common.h"
#include "dyld_cache.h"

typedef struct {
    uint32_t proc_enforce;
    uint32_t ret1_gadget;
    uint32_t pid_check;
    uint32_t locked_task;
    uint32_t i_can_has_debugger_1;
    uint32_t i_can_has_debugger_2;
    uint32_t mount_patch;
    uint32_t vm_map_enter;
    uint32_t vm_map_protect;
    uint32_t vm_fault_enter;
    uint32_t csops_patch;
    uint32_t csops_patch_size;
    uint32_t amfi_cred_label_update_execve;
    uint32_t amfi_vnode_check_signature;
    uint32_t amfi_loadEntitlementsFromVnode;
    uint32_t amfi_vnode_check_exec;
    uint32_t mapForIO;
    uint32_t sbcall_debugger;
    uint32_t vfsContextCurrent;
    uint32_t vnodeGetattr;
    uint32_t kernelConfig_stub;
    uint32_t sb_ops;
    uint32_t sb_disable;
    uint32_t sb_disable_size;
    uint32_t cs_system_require_lv;
    uint32_t amfi_cs_flags_patch;
} kernel_offsets_t;

typedef struct {
    struct {
        uint32_t pop_r4_r7_pc;
        uint32_t pop_r0_r1_r2_r3_r4_pc;
        uint32_t pop_r4_r5_r6_r7_pc;
        uint32_t ldr_r1_r2_4_bx_lr;
        uint32_t svc_0x80_bx_lr;
        uint32_t str_r0_r3_bx_lr;
        uint32_t pop_r2_r3_r7_pc;
        uint32_t ldr_r0_r2_bx_lr;
        uint32_t add_r0_r2_bx_lr;
        uint32_t str_r0_r2_bx_lr;
        uint32_t str_r2_r3_bx_lr;
        uint32_t add_r0_r1_bx_lr;
        uint32_t pop_r0_r1_pc;
        uint32_t str_r0_r1_bx_lr;
        uint32_t pop_r12_pc;
        uint32_t pop_lr_pc;
        uint32_t ldm_r1_r3_r5_r10_r11_r12_lr_pc;
        uint32_t ldm_r5_r0_r2_r4_r5_r8_r11_r12_pc;
        uint32_t ldm_r3_r1_r3_r9_r10_pc;
        uint32_t js_proto_lr;
        uint32_t rop_start;
    } gadgets;

    struct {
        uint32_t dlopen;
        uint32_t dlsym;
        uint32_t longjump;
        uint32_t syscall;
        uint32_t mach_msg_trap;
        uint32_t platform_memmove;
        uint32_t platform_memmove_lazy_ptr;
        uint32_t JSGlobalContextCreate;
        uint32_t JSContextGetGlobalObject;
        uint32_t JSStringCreateWithUTF8CString;
        uint32_t JSObjectSetProperty;
        uint32_t JSObjectGetProperty;
        uint32_t JSValueToObject;
        uint32_t JSValueMakeNumber;
        uint32_t JSObjectCallAsConstructor;
        uint32_t JSObjectMakeArray;
        uint32_t JSEvaluateScript;
    } symbols;

    struct {
        struct {
            uint32_t isakmp_cfg_addr;
            uint32_t lcconf_addr;
            uint32_t dns4_arr;
            uint32_t lcconf_counter;
            int32_t dns4_to_lcconf;
        } racoon;
        struct {
            uint32_t array_buffer;
            uint32_t byte_length;
            uint32_t mode;
        } data_view;
        kernel_offsets_t kernel;
    } offsets;

    struct {
        uint32_t stack_base;
    } stage1;

    struct {
        uint32_t stack_base;
        uint32_t stack_varibles;
        uint32_t stack_strings;
        uint32_t stack_size;
        uint32_t repair_local;
        uint32_t repair_start;
        uint32_t repair_end;
        uint32_t repair_offset;
    } stage2;

    struct {
        uint32_t mapping_base;
        uint32_t mapping_size;
    } stage3;

    struct {
        uint32_t max_slide;
        uint32_t region_base;
        uint32_t region_size;
        uint32_t remap_base;
        uint32_t remap_size;
        dsc_info_t *info;
    } dsc;
    uint32_t ios_version[3];
    bool use_dhcpd;
    bool unsafe_slide;
} procyon_ctx_t;

extern procyon_ctx_t *procyon;

void procyon_deinit(void);
int procyon_init(void);
int procyon_create_backup(void);
int procyon_restore_backup(void);

int gen_stage1(void);
int gen_stage2(void);
int gen_stage3(void);

#endif /* procyon_h */
