//
//  jailbreak.c
//  socket
//
//  Created by staturnz on 2/27/26.
//

#include "patchfinder.h"
#include "patches.h"
#include "util.h"
#include "exploit/oob_entry.h"
#include "exploit/memory.h"
#include "exploit/util.h"
#include "jailbreak.h"

void status(const char *str) {
    NSDictionary* data = @{@"msg": @[[NSString stringWithCString:str encoding:NSUTF8StringEncoding]]};
    [[NSNotificationCenter defaultCenter] postNotificationName:@"status" object:nil userInfo:data];
    usleep(10000);
}

int set_permissions(void) {
    for (uint32_t i = 0; i < 20; i++) {
        uint32_t kern_cred = kread32(kinfo->kern_proc_addr + koffsetof(proc, ucred));
        uint32_t ucred_pa = kvtophys(kread32(kinfo->self_proc_addr + koffsetof(proc, ucred)));
        physwrite32(ucred_pa + 0xc, 0);
        physwrite32(ucred_pa + 0x10, 0);
        physwrite32(ucred_pa + 0x14, 0);
        physwrite32(ucred_pa + 0x1c, 0);
        physwrite32(ucred_pa + 0x5c, 0);
        usleep(10000);
        
        setuid(0);
        setgid(0);
        seteuid(0);
        setegid(0);
        setruid(0);
        setrgid(0);
        
        kwrite32(kinfo->self_proc_addr + koffsetof(proc, ucred), kern_cred);
        usleep(100000);
        sync();
        
        kwrite32(kinfo->self_proc_addr + koffsetof(proc, ucred), kern_cred);
        usleep(100000);
        sync();
        
        setuid(0);
        setgid(0);
        seteuid(0);
        setegid(0);
        setruid(0);
        setrgid(0);
        if (getuid() == 0) return 0;
    }
    return (getuid() == 0) ? 0 : -1;
}

int remount_rootfs(void) {
    if (access("/", R_OK|W_OK) == 0) return 0;
    struct statfs st = {0};
    statfs("/", &st);

    char *dev = strdup("/dev/disk0s1s1");
    int rv = mount(st.f_fstypename, "/", MNT_UPDATE, &dev);
    free(dev);

    if (rv != 0) return -1;
    return access("/", R_OK|W_OK);
}

int update_zebra_sources(void) {
    mkdir(ZEBRA_SOURCES_PATH, 0755);
    chown(ZEBRA_SOURCES_PATH, 501, 501);

    unlink(ZEBRA_SOURCES_FILE);
    FILE *file = fopen(ZEBRA_SOURCES_FILE, "w+");
    if (file == NULL) return -1;
    
    fprintf(file, "%s\n", APT_TELESPHOREO_REPO);
    fprintf(file, "%s\n", APT_BIGBOSS_REPO);
    fprintf(file, "%s\n", APT_MODMYI);
    fprintf(file, "%s\n", APT_CHARIZ_REPO);
    fprintf(file, "%s\n", APT_PACKIX_REPO);
    fprintf(file, "%s\n", APT_HAVOC_REPO);
    fprintf(file, "%s\n", APT_ZEBRA_REPO);
    fprintf(file, "%s\n", APT_LUKEZGD_REPO);

    fflush(file);
    fclose(file);
    sync();
    return 0;
}

static void show_non_default_apps(void) {
    NSMutableDictionary *dict = [[NSMutableDictionary alloc] initWithContentsOfFile:@"/var/mobile/Library/Preferences/com.apple.springboard.plist"];
    [dict setObject:[NSNumber numberWithBool:YES] forKey:@"SBShowNonDefaultSystemApps"];
    [dict writeToFile:@"/var/mobile/Library/Preferences/com.apple.springboard.plist" atomically:YES];
    run_bin("/usr/bin/killall", true, 2, "-9", "cfprefsd");

    chmod("/private", 0777);
    chmod("/private/var", 0777);
    chmod("/private/var/mobile", 0777);
    chmod("/private/var/mobile/Library", 0777);
    chmod("/private/var/mobile/Library/Preferences", 0777);
}

int fixup_package_managers(bool first_install) {
    if (!first_install && file_exists("/var/cache/.socket_1_2")) return 0;
    if (!file_exists("/.cydia_no_stash")) {
        create_dotfile("/.cydia_no_stash");
    }
    
    bool has_firmware = false;
    bool old_zebra = false;
    uint32_t status_size = 0;
    char *status_file = map_file("/var/lib/dpkg/status", &status_size);
    
    if (status_file != NULL) {
        has_firmware = (memmem(status_file, status_size, "Name: iOS Firmware", strlen("Name: iOS Firmware")) != NULL);
        old_zebra = (memmem(status_file, status_size, "1.1.28-L1-19", strlen("1.1.28-L1-19")) != NULL);
        unmap_file(status_file, status_size);
    }
    
    if (!has_firmware && file_exists("/usr/libexec/cydia/firmware.sh")) {
        run_bin("/bin/sh", true, 2, "-c", "/usr/libexec/cydia/firmware.sh");
    }
    
    if (old_zebra) {
        print_log("[*] updating zebra...\n");
        install_deb(bundle_path("zebra.deb"));
    }
    
    show_non_default_apps();
    update_zebra_sources();
    uicache();
    return 0;
}

void verify_install(void) {
    if (!file_exists("/Applications/Zebra.app/Zebra") && !file_exists("/Applications/Cydia.app/Cydia")) {
        fixup_package_managers(true);
    } else {
        NSMutableDictionary *dict = [[NSMutableDictionary alloc] initWithContentsOfFile:@"/var/mobile/Library/Preferences/com.apple.springboard.plist"];
        if (dict != NULL) {
            NSNumber *value = [dict objectForKey:@"SBShowNonDefaultSystemApps"];
            if (value == NULL || ![value isEqualToNumber:@(1)]) {
                show_non_default_apps();
                uicache();
            }
        }
    }
    
    if (!file_exists("/bin/tar")) {
        copy_bundle_file("tar", "/bin/tar", 0755, 0, 0);
        int fd = open("/bin/tar", O_RDWR);
        if (fd >= 0) {
            uint32_t magic = FAT_CIGAM;
            write(fd, &magic, sizeof(magic));
            fsync(fd);
            close(fd);
        }
    }
    
    if (!file_exists("/bin/launchctl")) {
        copy_bundle_file("launchctl", "/bin/launchctl", 0755, 0, 0);
        int fd = open("/bin/launchctl", O_RDWR);
        if (fd >= 0) {
            uint32_t magic = FAT_CIGAM;
            write(fd, &magic, sizeof(magic));
            fsync(fd);
            close(fd);
        }
    }
    
    if (!file_exists("/.cydia_no_stash")) {
        create_dotfile("/.cydia_no_stash");
    }
    
    if (!file_exists("/.installed_socket")) {
        create_dotfile("/.installed_socket");
    }
    
    [[NSUserDefaults standardUserDefaults] setObject:@"no" forKey:@"restrap"];
    [[NSUserDefaults standardUserDefaults] synchronize];
    
    flush_volume("/private/var");
    flush_volume("/");
    usleep(100000);
    sync();
}

int install_bootstrap(void) {
    if (!file_exists("/bin/tar")) {
        copy_bundle_file("tar", "/bin/tar", 0755, 0, 0);
        int fd = open("/bin/tar", O_RDWR);
        if (fd < 0) return -1;
        

        uint32_t magic = FAT_CIGAM;
        write(fd, &magic, sizeof(magic));
        close(fd);
    }
    
    if (!file_exists("/bin/launchctl")) {
        copy_bundle_file("launchctl", "/bin/launchctl", 0755, 0, 0);
        int fd = open("/bin/launchctl", O_RDWR);
        if (fd < 0) return -1;
        
        uint32_t magic = FAT_CIGAM;
        write(fd, &magic, sizeof(magic));
        close(fd);
    }

    status("[*] installing bootstrap...\n");
    extract_tar(bundle_path("bootstrap.tar"), "/");

    status("[*] installing zebra...\n");
    install_deb(bundle_path("zebra.deb"));

    chmod("/private/var/mobile/Library/Preferences", 0777);
    fixup_package_managers(true);
    
    create_dotfile("/.cydia_no_stash");
    create_dotfile("/.installed_socket");
    return 0;
}

int install_untether(void) {
    status("[*] installing untether...\n");
    return install_deb(bundle_path("procyon.deb"));
}

void load_daemons(void) {
    run_bin("/bin/launchctl", true, 2, "unload", "/System/Library/NanoLaunchDaemons");
    run_bin("/bin/launchctl", true, 2, "load", "/System/Library/LaunchDaemons");
    run_bin("/bin/launchctl", true, 2, "load", "/System/Library/NanoLaunchDaemons");
    run_bin("/bin/launchctl", true, 2, "unload", "/Library/LaunchDaemons/com.openssh.sshd.plist");
    run_bin("/bin/launchctl", true, 2, "load", "/Library/LaunchDaemons");

    run_bin("/usr/libexec/sshd-keygen-wrapper", false, 0);
    run_bin("/bin/bash", true, 2, "-c", "ls /Library/LaunchDaemons |\
        while read a; do launchctl load /Library/LaunchDaemons/$a; done; ls /etc/rc.d |\
        while read a; do /etc/rc.d/$a; done;");
}

int run_jailbreak(uint32_t flags) {
    status("[*] running exploit...\n");
    if (run_oob_entry(false) != 0) {
        status("[-] exploit failed\n");
        return -1;
    }
    
    status("[*] setting permissions...\n");
    if (set_permissions() != 0) {
        status("[-] failed to set permissions\n");
        return -1;
    }
    
    status("[*] applying patches...\n");
    if (apply_patches() != 0) {
        status("[-] failed to patch kernel\n");
        return -1;
    }
    
    status("[*] remounting rootfs...\n");
    if (remount_rootfs() != 0) {
        status("[-] failed to remount rootfs\n");
        return -1;
    }
    
    status("[*] rootfs remounted\n");
    if (access("/.installed_socket", F_OK) != 0 || (flags & JB_FLAG_BOOTSTRAP)) {
        if (install_bootstrap() != 0) {
            status("[-] failed to install bootstrap\n");
            return -1;
        }
    } else {
        fixup_package_managers(false);
    }
    
    if (access("/var/root/procyon", F_OK) != 0 && (flags & JB_FLAG_UNTETHER)) {
        if (install_untether() != 0) {
            status("[-] failed to install untether\n");
            return -1;
        }
    }
    create_dotfile("/var/cache/.socket_1_2");
    if ((flags & JB_FLAG_TWEAKS)) {
        status("[*] loading daemons...\n");
        load_daemons();
    }
    
    verify_install();
    print_log("[*] done!\n");
    if ((flags & JB_FLAG_RESPRING)) {
        usleep(500000);
        run_bin("/usr/bin/killall", true, 2, "-9", "backboardd");
        run_bin("/usr/bin/killall", true, 2, "-9", "SpringBoard");
    }
    return 0;
}
