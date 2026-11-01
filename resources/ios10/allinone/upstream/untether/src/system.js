
var sys = {
    __mach_task_self: undefined,
    __mach_host_self: undefined,
    __mach_reply_port: undefined,
    __IOSurfaceCreate_ptr: undefined,
    __IOSurfaceGetBaseAddress_ptr: undefined,
    __CFStringCreateWithCString_ptr: undefined,
    __CFNumberCreate_ptr: undefined,
    __CFDictionaryCreateMutable_ptr: undefined,
    __CFDictionarySetValue_ptr: undefined,
    
    mach_task_self: function() {
        if (sys.__mach_task_self == undefined) {
            sys.__mach_task_self = util.syscall(0xFFFFFFE4);
        }
        return sys.__mach_task_self;
    },

    mach_host_self: function() {
        if (sys.__mach_host_self == undefined) {
            sys.__mach_host_self = util.syscall(0xFFFFFFE3);
        }
        return sys.__mach_host_self;
    },

    mach_thread_self: function() {
        return util.syscall(0xFFFFFFE5);
    },
        
    mach_reply_port: function() {
        if (sys.__mach_reply_port == undefined) {
            sys.__mach_reply_port = util.syscall(0xFFFFFFE6);
        }
        return sys.__mach_reply_port;
    },
    
    mach_vm_allocate: function(target, address, size, flags) {
        return util.syscall(0xFFFFFFF6, target, address, size, 0, flags);
    },
    
    mach_vm_deallocate: function(target, address, size) {
        return util.syscall(0xFFFFFFF4, target, address, 0, size, 0);
    },
    
    mach_port_allocate: function(task, right, port_addr) {
        return util.syscall(0xFFFFFFF0, task, right, port_addr);
    },
    
    mach_port_destroy: function(task, port) {
        return util.syscall(0xFFFFFFEF, task, port);
    },
    
    mach_port_insert_right: function(task, name, port, right) {
        return util.syscall(0xFFFFFFED, task, name, port, right);
    },

    mach_msg: function(hdr_addr, opt, send_size, recv_size, recv_name, timeout, notify) {
        return util.syscall(0xFFFFFFE1, hdr_addr, opt, send_size, recv_size, recv_name, timeout, notify);
    },
    
    thread_switch: function(thread_name, option, option_time) {
        return util.syscall(0xFFFFFFC3, thread_name, option, option_time);
    },
    
    exit: function(code) {
        return util.syscall(1, code);
    },

    kill: function(pid, signum) {
        return util.syscall(37, pid, signum, 0);
    },

    open: function(path, flags, mode) {
        return util.syscall(5, path, flags, mode);
    },
    
    close: function(fd) {
        return util.syscall(6, fd);
    },

    setuid: function(uid) {
        return util.syscall(23, uid);
    },

    getuid: function() {
        return util.syscall(24);
    },

    access: function(path, flags) {
        return util.syscall(33, path, flags);
    },

    sync: function() {
        return util.syscall(36);
    },

    reboot: function(opt) {
        return util.syscall(55, opt);
    },

    socket: function(domain, type, protocol) {
        return util.syscall(97, domain, type, protocol);
    },

    setsockopt: function(fd, level, name, val_addr, val_size) {
        return util.syscall(105, fd, level, name, val_addr, val_size);
    },

    getsockopt: function(fd, level, name, val_addr, val_size) {
        return util.syscall(118, fd, level, name, val_addr, val_size);
    },

    mount: function(type, path, flags, data) {
        return util.syscall(167, type, path, flags, data);
    },

    setgid: function(gid) {
        return util.syscall(181, gid);
    },
    
    getgid: function() {
        return util.syscall(47);
    },

    setegid: function(egid) {
        return util.syscall(182, egid);
    },

    seteuid: function(euid) {
        return util.syscall(183, euid);
    },
    
    geteuid: function() {
        return util.syscall(25);
    },
    
    getegid: function() {
        return util.syscall(43);
    },
    
    setruid: function(ruid) {
        return util.syscall(126, ruid, sys.geteuid());
    },
    
    setrgid: function(rgid) {
        return util.syscall(127, rgid, sys.getegid());
    },

    disconnectx: function(s, aid, cid) {
        return util.syscall(448, s, aid, cid);
    },
    
    mach_make_memory_entry_64: function(task, size, offset, prot, handle_ptr, entry) {
        var msg = util.mig_setup(0xef1, 0x44, 0x40, task, true);
        util.mig_set_ndr(msg, 0x28);
        util.mig_set_descriptor(msg, 0x1c, entry);

        msg.write(0x30, size[1], 0x4);
        msg.write(0x34, size[0], 0x4);
        msg.write(0x38, offset[1], 0x4);
        msg.write(0x3c, offset[0], 0x4);
        msg.write(0x40, prot, 0x4);

        var status = util.mig_send(msg);
        if (status != 0) return status;
        
        var handle = msg.read(0x1c, 0x4);
        mem.write32(handle_ptr, handle);
        return (handle != 0) ? 0 : -1;
    },
    
    mach_vm_map: function(task, address_ptr, size, mask, flags, object, offset, copy, cur_prot, max_prot, inheritance) {
        var msg = util.mig_setup(0x12cb, 0x64, 0x34, task, true);
        util.mig_set_ndr(msg, 0x28);
        util.mig_set_descriptor(msg, 0x1c, object);

        msg.write(0x30, mem.read32(address_ptr), 0x4);
        msg.write(0x34, 0, 0x4);
        msg.write(0x38, size, 0x4);
        msg.write(0x3c, 0, 0x4);
        msg.write(0x40, 0, 0x4);
        msg.write(0x44, 0, 0x4);
        msg.write(0x48, flags, 0x4);
        msg.write(0x4c, offset, 0x4);
        msg.write(0x50, 0, 0x4);
        msg.write(0x54, copy, 0x4);
        msg.write(0x58, cur_prot, 0x4);
        msg.write(0x5c, max_prot, 0x4);
        msg.write(0x60, inheritance, 0x4);
        
        mem.write32(address_ptr, 0);
        var status = util.mig_send(msg);
        if (status != 0) return status;
        
        status = msg.read(0x20, 0x4);
        if (status != 0) return status;

        var addr = msg.read(0x24, 0x4);
        mem.write32(address_ptr, addr);
        return (addr != 0) ? 0 : -1;
    },
    
    task_get_special_port: function(task, which_port, special_port) {
        var msg = util.mig_setup(0xD51, 0x24, 0x30, task, false);
        util.mig_set_ndr(msg, 0x18);
        msg.write(0x20, which_port, 0x4);
        
        var status = util.mig_send(msg);
        if (status != 0) return status;
        
        var port = msg.read(0x1c, 0x4);
        if (port == 0 || port == 1) port = MACH_PORT_NULL;
        
        mem.write32(special_port, port);
        return (port != 0) ? 0 : -1;
    },
    
    mach_vm_read: function(task, addr, size, data, out_size) {
        var msg = util.mig_setup(0x12C8, 0x38, 0x34, task, false);
        util.mig_set_ndr(msg, 0x18);
        
        msg.write(0x20, addr, 0x4);
        msg.write(0x28, size, 0x4);
        msg.write(0x30, data, 0x4);
        
        var status = util.mig_send(msg);
        if (status != 0) return status;
        
        status = msg.read(0x20, 0x4);
        if (status != 0) return status;

        if (out_size) mem.write32(out_size, msg.read(0x24, 0x4));
        return 0;
    },

    mach_vm_write: function(task, addr, data, size) {
        var msg = util.mig_setup(0x12C6, 0x3c, 0x2c, task, true);
        util.mig_set_ndr(msg, 0x28);
        msg.write(0x18, 1, 0x4);

        msg.write(0x1c, data, 0x4);
        msg.write(0x20, size, 0x4);
        msg.write(0x24, 0x01000100, 0x4);
        
        msg.write(0x30, addr, 0x4);
        msg.write(0x38, size, 0x4);
        
        var status = util.mig_send(msg);
        if (status != 0) return status;
        return msg.read(0x20, 0x4);
    },
    
    mach_vm_msync: function(task, addr, size, flags) {
        var msg = util.mig_setup(0x12C9, 0x34, 0x2c, task, false);
        util.mig_set_ndr(msg, 0x18);
        
        msg.write(0x20, addr, 0x4);
        msg.write(0x28, size, 0x4);
        msg.write(0x30, size, flags);
        
        var status = util.mig_send(msg);
        if (status != 0) return status;
        return msg.read(0x20, 0x4);
    },
    
    posix_spawn: function(pid, path, adesc, argv, envp) {
        return util.syscall(244, pid, path, adesc, argv, envp);
    },
    
    waitpid: function(pid, status, options) {
        return util.syscall(7, pid, status, options, 0);
    },
    
    IOSurfaceCreate: function(dict) {
        if (sys.__IOSurfaceCreate_ptr == undefined) {
            sys.__IOSurfaceCreate_ptr = dyld.find(IOSURFACE_PATH, "IOSurfaceCreate");
        }
        return util.call(sys.__IOSurfaceCreate_ptr, dict);
    },
    
    IOSurfaceGetBaseAddress: function(surface) {
        if (sys.__IOSurfaceGetBaseAddress_ptr == undefined) {
            sys.__IOSurfaceGetBaseAddress_ptr = dyld.find(IOSURFACE_PATH, "IOSurfaceGetBaseAddress");
        }
        return util.call(sys.__IOSurfaceGetBaseAddress_ptr, surface);
    },
    
    CFSTR: function(str) {
        if (sys.__CFStringCreateWithCString_ptr == undefined) {
            sys.__CFStringCreateWithCString_ptr = dyld.find(CF_PATH, "CFStringCreateWithCString");
        }
        return util.call(sys.__CFStringCreateWithCString_ptr, 0, util.cstr(str), 0x08000100);
    },
    
    CFNUM: function(value) {
        if (sys.__CFNumberCreate_ptr == undefined) {
            sys.__CFNumberCreate_ptr = dyld.find(CF_PATH, "CFNumberCreate");
        }
        
        var data = util.create_data_buf(0x10);
        data.write(0x0, value, 0x4);
        return util.call(sys.__CFNumberCreate_ptr, 0, 9, data.addr);
    },
        
    CFDictionaryCreateMutable: function(allocator, capacity, keyCallBacks, valueCallBacks) {
        if (sys.__CFDictionaryCreateMutable_ptr == undefined) {
            sys.__CFDictionaryCreateMutable_ptr = dyld.find(CF_PATH, "CFDictionaryCreateMutable");
        }
        return util.call(sys.__CFDictionaryCreateMutable_ptr, allocator, capacity, keyCallBacks, valueCallBacks);
    },
    
    CFDictionarySetValue: function(dict, key, value) {
        if (sys.__CFDictionarySetValue_ptr == undefined) {
            sys.__CFDictionarySetValue_ptr = dyld.find(CF_PATH, "CFDictionarySetValue");
        }
        return util.call(sys.__CFDictionarySetValue_ptr, dict, key, value);
    }
};
