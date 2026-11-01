
var dyld = {
    dlopen_ptr: undefined,
    dlsym_ptr: undefined,
    cache_slide: undefined,
    handle_cache: undefined,
    base_region: undefined,
    remap_region: undefined,

    init: function() {
        dyld.cache_slide = mem.read32(0x12000200);
        dyld.dlopen_ptr = util.u32(info.symbols.dlopen) + dyld.cache_slide;
        dyld.dlsym_ptr = util.u32(info.symbols.dlsym) + dyld.cache_slide;
        dyld.base_region = util.u32(0x1a000000);
        dyld.remap_region = util.u32(info.remap_base);
        dyld.handle_cache = [];
    },
    
    dlopen: function(path, mode) {
        if (dyld.handle_cache[path] != undefined) {
            return dyld.handle_cache[path];
        }
        
        var handle = util.call(dyld.dlopen_ptr, util.cstr(path), mode);
        if (handle != 0) dyld.handle_cache[path] = handle;
        return handle;
    },
    
    dlsym: function(handle, name) {
        return util.call(dyld.dlsym_ptr, handle, util.cstr(name));
    },

    slide_addr: function(addr) {
        return util.u32(addr) + dyld.cache_slide;
    },

    remap_addr: function(addr) {
        return (util.u32(addr) - dyld.base_region) + dyld.remap_region;
    },
    
    find: function(path, name, remap) {
        var handle = dyld.dlopen(path, RTLD_NOW);
        if (handle == 0) return nullptr;

        var addr = dyld.dlsym(handle, name);
        if (addr == 0) return nullptr;

        if (remap) {
            addr = dyld.remap_addr(addr - dyld.cache_slide);
        }
        return util.u32(addr);
    }
};
