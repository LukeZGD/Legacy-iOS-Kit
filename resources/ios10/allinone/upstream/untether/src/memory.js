
var mem = {
    scratch: undefined,
    
    addrof: function(object) {
        if (object == undefined || object == null) return util.u32(0);
        arr_addrof[0] = object;
        return dv_addrof.getUint32(0, true);
    },

    read8: function(addr) {
        if (addr < 0x1000) return 0;
        return dv_rw.getUint8(addr);
    },
    
    write8: function(addr, value) {
        if (addr < 0x1000) return;
        dv_rw.setUint8(addr, value & 0xff);
    },
    
    read32: function(addr) {
        if (addr < 0x1000) return 0;
        return dv_rw.getUint32(addr, true);
    },

    write32: function(addr, value) {
        if (addr < 0x1000) return;
        dv_rw.setUint32(addr, value & 0xffffffff, true);
    },
    
    copy: function(dest, src, size) {
        if (dest < 0x1000 || src < 0x1000 || size == 0) return;
        for (var i = 0; i < size; i++) {
            mem.write8(dest+i, mem.read8(src+i));
        }
    },
    
    allocate: function(size) {
        if (size <= 0) return 0;
        var task = sys.mach_task_self();
        var data = util.create_data_buf(0x10);

        sys.mach_vm_allocate(task, data.addr, size, VM_FLAGS_ANYWHERE);
        return data.read(0x0, 0x4);
    },
    
    deallocate: function(addr, size) {
        if (addr == 0 || size <= 0) return 0;
        var task = sys.mach_task_self();
        sys.mach_vm_allocate(task, 0, addr, size);
    },
    
    init: function() {
        mem.scratch = mem.allocate(0x1000);
    }
};
