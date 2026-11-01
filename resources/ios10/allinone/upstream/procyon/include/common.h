#ifndef procyon_common_h
#define procyon_common_h

#include <stdio.h>
#include <stdlib.h>
#include <stdbool.h>
#include <stdarg.h>
#include <unistd.h>
#include <string.h>
#include <errno.h>
#include <fcntl.h>
#include <time.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/file.h>
#include <sys/sysctl.h>
#include <sys/syscall.h>
#include <mach/mach.h>
#include <mach-o/loader.h>
#include <mach-o/dyld.h>
#include <mach-o/dyld_images.h>
#include <mach-o/nlist.h>
#include <dlfcn.h>
#include <mach/mach_traps.h>
#include <sys/socket.h>
#include <sys/syslog.h>
#include <limits.h>
#include <netinet/in.h>
#include <sys/types.h>
#include <netinet/ip6.h>
#include <TargetConditionals.h>
#include <CoreFoundation/CoreFoundation.h>
#include <dirent.h>
#include <libgen.h>
#include <spawn.h>

typedef union {
    double f64;
    struct {
        uint32_t lo;
        uint32_t hi;
    } u32;
} f64_u32_t;

typedef union {
    uint32_t addr;
    char buf[4];
} addr_converter_t;

typedef struct {
    const char *name;
    uint32_t addr;
    uint32_t size;
} rop_variable_t;

#define STATIC_WRITE8(offset, value) { *(uint8_t *)(stage2_data + offset) = (uint8_t)(value); }
#define STATIC_WRITE16(offset, value) { *(uint16_t *)(stage2_data + offset) = (uint16_t)(value); }
#define STATIC_WRITE32(offset, value) { *(uint32_t *)(stage2_data + offset) = (uint32_t)(value); }
#define STATIC_WRITE64(offset, value) { *(uint64_t *)(stage2_data + offset) = (uint64_t)(value); }
#define DSC_REMAP_ADDR(addr) ((addr - procyon->dsc.region_base) + procyon->dsc.remap_base)

#endif /* procyon_common_h */
