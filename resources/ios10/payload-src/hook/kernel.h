#include <stdint.h>

#define PHYS_TO_VIRT(x) (((uintptr_t)x - (uintptr_t)phys_base) + (uintptr_t)virt_base)
#define VIRT_TO_PHYS(x) (((uintptr_t)x - (uintptr_t)virt_base) + (uintptr_t)phys_base)

typedef uint16_t insn_t;

#define NOP (0xBF00)
#define MOVS_R0_0 (0x2000)
#define MOVS_R0_1 (0x2001)
#define MOVS_R0_C (0x200C)
#define BX_LR (0x4770)

uintptr_t* find_sbops(uintptr_t phys_base, uint32_t ksize);

/* sym */
uint32_t find_PE_i_can_has_debugger(uint32_t phys_base, uint32_t virt_base);
uint32_t find_vfs_context_current(uint32_t phys_base, uint32_t virt_base);
uint32_t find_vnode_getattr(uint32_t phys_base, uint32_t virt_base);

uint32_t find_pid_check(uint32_t phys_base, uint32_t ksize);
uint32_t find_convert_port_to_locked_task(uint32_t phys_base, uint32_t ksize);
uint32_t find_mount_103(uint32_t phys_base, uint32_t ksize);
uint32_t find_mount_union(uint32_t phys_base, uint32_t ksize);
uint32_t find_vm_map_enter_103(uint32_t phys_base, uint32_t ksize);
uint32_t find_vm_map_protect_103(uint32_t phys_base, uint32_t ksize);
uint32_t find_csops_103(uint32_t phys_base, uint32_t ksize);
uint32_t find_vm_fault_enter_103(uint32_t phys_base, uint32_t ksize);

uint32_t find_amfi_execve_ret(uint32_t phys_base, uint32_t ksize);
uint32_t find_mapForIO_103(uint32_t phys_base, uint32_t ksize);
uint32_t find_sandbox_call_i_can_has_debugger_103(uint32_t phys_base, uint32_t ksize);
uint32_t find_amfi_cred_label_update_execve(uint32_t phys_base, uint32_t ksize);
uint32_t find_amfi_vnode_check_signature(uint32_t phys_base, uint32_t ksize);
uint32_t find_amfi_loadEntitlementsFromVnode(uint32_t phys_base, uint32_t ksize);
uint32_t find_amfi_vnode_check_exec(uint32_t phys_base, uint32_t ksize);
uint32_t find_lwvm_i_can_has_krnl_conf_stub(uint32_t phys_base, uint32_t ksize);

uint32_t find_last_text_region(uint32_t phys_base);
uint32_t find_prepare_and_jump(uint32_t iboot_base, uint32_t isize);

uint32_t find_launchd(uint32_t phys_base, uint32_t ksize);

#define    LC_SEGMENT    0x1    /* segment of this file to be mapped */
#define    LC_SYMTAB    0x2    /* link-edit stab symbol table info */
#define    LC_UNIXTHREAD    0x5    /* unix thread (includes a stack) */
#define LC_VERSION_MIN_IPHONEOS 0x25

#define SEGMENT_DATA "__DATA"
#define    SEG_LINKEDIT    "__LINKEDIT"    /* the segment containing all structs */


typedef uint32_t vm_address_t;
typedef int    vm_prot_t;
typedef int    cpu_type_t;
typedef int    cpu_subtype_t;

struct load_command {
    uint32_t cmd;        /* type of load command */
    uint32_t cmdsize;    /* total size of command in bytes */
};

struct mach_header {
    uint32_t    magic;        /* mach magic number identifier */
    cpu_type_t    cputype;    /* cpu specifier */
    cpu_subtype_t    cpusubtype;    /* machine specifier */
    uint32_t    filetype;    /* type of file */
    uint32_t    ncmds;        /* number of load commands */
    uint32_t    sizeofcmds;    /* the size of all the load commands */
    uint32_t    flags;        /* flags */
};

struct segment_command { /* for 32-bit architectures */
    uint32_t    cmd;        /* LC_SEGMENT */
    uint32_t    cmdsize;    /* includes sizeof section structs */
    char        segname[16];    /* segment name */
    uint32_t    vmaddr;        /* memory address of this segment */
    uint32_t    vmsize;        /* memory size of this segment */
    uint32_t    fileoff;    /* file offset of this segment */
    uint32_t    filesize;    /* amount to map from the file */
    vm_prot_t    maxprot;    /* maximum VM protection */
    vm_prot_t    initprot;    /* initial VM protection */
    uint32_t    nsects;        /* number of sections in segment */
    uint32_t    flags;        /* flags */
};

struct version_min_command {
    uint32_t    cmd;        /* LC_VERSION_MIN_MACOSX or
                             LC_VERSION_MIN_IPHONEOS or
                             LC_VERSION_MIN_WATCHOS or
                             LC_VERSION_MIN_TVOS */
    uint32_t    cmdsize;    /* sizeof(struct min_version_command) */
    uint32_t    version;    /* X.Y.Z is encoded in nibbles xxxx.yy.zz */
    uint32_t    sdk;        /* X.Y.Z is encoded in nibbles xxxx.yy.zz */
};

struct section { /* for 32-bit architectures */
    char        sectname[16];    /* name of this section */
    char        segname[16];    /* segment this section goes in */
    uint32_t    addr;        /* memory address of this section */
    uint32_t    size;        /* size in bytes of this section */
    uint32_t    offset;        /* file offset of this section */
    uint32_t    align;        /* section alignment (power of 2) */
    uint32_t    reloff;        /* file offset of relocation entries */
    uint32_t    nreloc;        /* number of relocation entries */
    uint32_t    flags;        /* flags (section type and attributes)*/
    uint32_t    reserved1;    /* reserved (for offset or index) */
    uint32_t    reserved2;    /* reserved (for count or sizeof) */
};

struct symtab_command {
    uint32_t    cmd;        /* LC_SYMTAB */
    uint32_t    cmdsize;    /* sizeof(struct symtab_command) */
    uint32_t    symoff;        /* symbol table offset */
    uint32_t    nsyms;        /* number of symbol table entries */
    uint32_t    stroff;        /* string table offset */
    uint32_t    strsize;    /* string table size in bytes */
};

struct nlist {
    union {
        uint32_t n_strx;    /* index into the string table */
    } n_un;
    uint8_t n_type;        /* type flag, see below */
    uint8_t n_sect;        /* section number or NO_SECT */
    int16_t n_desc;        /* see <mach-o/stab.h> */
    uint32_t n_value;    /* value of this symbol (or stab offset) */
};

struct thread_command {
    uint32_t    cmd;        /* LC_THREAD or  LC_UNIXTHREAD */
    uint32_t    cmdsize;    /* total size of this command */
    uint32_t flavor;        /* flavor of thread state */
    uint32_t count;            /* count of longs in thread state */
    /* struct XXX_thread_state state   thread state for this flavor */
    /* ... */
};

struct arm_thread_state
{
    uint32_t    r[13];    /* General purpose register r0-r12 */
    uint32_t    sp;        /* Stack pointer r13 */
    uint32_t    lr;        /* Link register r14 */
    uint32_t    pc;        /* Program counter r15 */
    uint32_t    cpsr;        /* Current program status register */
};

typedef struct {
    uint32_t num_args;
    uint32_t handler;
    uint32_t num_u32;
} mach_trap_t;

typedef struct {
    uint32_t num_args;
    uint32_t handler;
} mach_trap_old_t;
