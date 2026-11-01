
const CF_PATH = "/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation";
const IOSURFACE_PATH = "/System/Library/PrivateFrameworks/IOSurface.framework/IOSurface";
const nullptr = ((0x00000000 & 0xffffffff) >>> 0);

const VM_FLAGS_ANYWHERE = 0x0001;
const VM_FLAGS_NO_CACHE = 0x0010;
const VM_PROT_READ = 0x01;
const VM_PROT_WRITE = 0x02;
const IPPROTO_TCP = 6;
const SOCK_STREAM = 1;
const AF_INET6 = 30;
const SONPX_SETOPTSHUT = 0x000000001;
const SOL_SOCKET = 0xffff;
const SO_NP_EXTENSIONS = 0x1083;
const IPPROTO_IPV6 = 41;
const IPV6_USE_MIN_MTU = 42;
const IPV6_PKTINFO = 46;
const IPV6_PREFER_TEMPADDR = 63;
const MACH_PORT_NULL = 0x0;
const MACH_PORT_RIGHT_RECEIVE = 0x1;
const MACH_MSG_TYPE_MAKE_SEND = 0x14;
const MACH_MSG_TYPE_COPY_SEND = 0x13;
const MACH_MSG_OOL_PORTS_DESCRIPTOR = 0x2;
const MACH_MSG_PHYSICAL_COPY = 0x0;
const MACH_SEND_MSG = 0x1;
const OOL_MSG_BITS = 0x80000014;
const RTLD_NOW = 0x2;
const MH_MAGIC = 0xfeedface;
const MH_EXECUTE = 0x2;
const LC_SEGMENT = 0x1;
const MNT_UPDATE = 0x00010000;
const W_OK = (1<<1);
const R_OK = (1<<2);
const F_OK = 0;
const VM_SYNC_SYNCHRONOUS = 0x02;
const VM_SYNC_INVALIDATE = 0x04;
const O_RDONLY = 0x0000;

var kinfo = {
    self_port_addr: 0x0,
    self_task_addr: 0x0,
    self_proc_addr: 0x0,
    kern_port_addr: 0x0,
    kern_task_addr: 0x0,
    kern_proc_addr: 0x0,
    kern_vm_map: 0x0,
    kern_pmap: 0x0,
    kern_ttep: 0x0,
    kern_tte: 0x0,
    kern_data_pa: 0x0,
    kern_data_size: 0x0,
    main_entry: MACH_PORT_NULL,
    oob_entry: MACH_PORT_NULL,
    tfp0: MACH_PORT_NULL,
    mapping_base: 0x0,
    kernel_base: 0x0,
    kernel_slide: 0x0,
    kernel_static_base: 0x80001000,
    kernel_phys_base: 0x80001000,
    mem_base: 0x80000000,
    cr_gmuid_ptr: 0x0,
    orig_data: undefined,
    use_tfp0: false
};

var offsets = {
    mach_msg_hdr: {
        msgh_bits: 0x0,
        msgh_size: 0x4,
        msgh_remote_port: 0x8,
        msgh_local_port: 0xc,
        msgh_voucher_port: 0x10,
        msgh_id: 0x14
    },
    mach_msg_body: {
        msgh_descriptor_count: 0x18
    },
    ool_msg: {
        size: 0x28,
        ool_ports: {
            address: 0x1c,
            count: 0x20,
            deallocate: 0x24,
            copy: 0x25,
            disposition: 0x26,
            type: 0x27
        }
    },
    task: {
        vm_map: 0x14,
        next: 0x18,
        prev: 0x1c,
        bsd_info: 0x22c,
        ref_count: 0x8,
        itk_self: 0x9c,
        itk_seatbelt: 0x1c8,
        itk_space: 0x1e8
    },
    proc: {
        next: 0x4,
        pid: 0x8,
        task: 0xc,
        ucred: 0x98,
        p_fd: 0x9c,
        lock_type: 0x48,
        p_stat: 0x4c
    },
    ipc_port: {
        ip_kobject: 0x48
    },
    vm_map: {
        pmap: 0x28
    },
    pmap: {
        tte: 0x0,
        ttep: 0x4
    },
    file_desc: {
        fd_ofiles: 0x0,
    },
    file_proc: {
        f_fglob: 0x8,
    },
    file_glob: {
        fg_data: 0x28,
    },
    vnode: {
        namecache: 0x20,
        kusecount: 0x38,
        usecount: 0x3c
    },
    namecache: {
        vnode: 0x24
    },
    mpo: {
        cred_label_update_execve: 0x48,
        mount_check_mount: 0x15C,
        mount_check_remount: 0x160,
        mount_check_umount: 0x16C,
        vnode_check_write: 0x470,
        file_check_mmap: 0x90,
        vnode_check_rename: 0x1E0,
        vnode_check_access: 0x3F0,
        vnode_check_chroot: 0x3F8,
        vnode_check_create: 0x3FC,
        vnode_check_deleteextattr: 0x400,
        vnode_check_exchangedata: 0x404,
        vnode_check_exec: 0x408,
        vnode_check_getattrlist: 0x40C,
        vnode_check_getextattr: 0x410,
        vnode_check_ioctl: 0x414,
        vnode_check_link: 0x420,
        vnode_check_listextattr: 0x424,
        vnode_check_open: 0x42C,
        vnode_check_readlink: 0x438,
        vnode_check_setattrlist: 0x44C,
        vnode_check_setextattr: 0x450,
        vnode_check_setflags: 0x454,
        vnode_check_setmode: 0x458,
        vnode_check_setowner: 0x45C,
        vnode_check_setutimes: 0x460,
        vnode_check_stat: 0x464,
        vnode_check_truncate: 0x468,
        vnode_check_unlink: 0x46C,
        vnode_notify_create: 0x4BC,
        vnode_check_fsgetpath: 0x4F0,
        vnode_check_getattr: 0x3D4,
        mount_check_stat: 0x168,
        proc_check_setauid: 0x29C,
        proc_check_getauid: 0x288,
        proc_check_fork: 0x278,
        proc_check_get_cs_info: 0x3E4,
        proc_check_set_cs_info: 0x3E8
    }
};

var koffsetof = function(struct, entry) {
    return offsets[struct][entry];
}
