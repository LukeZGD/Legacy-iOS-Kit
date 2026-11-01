/*
 * hook payload
 * copyright (C) 2021/11/14 sakuRdev
 *
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 */

#include "lib/aeabi.h"
#include "lib/putc.h"
#include "lib/printf.h"
#include "lib/lib.h"

#include "drivers/drivers.h"
#include "drivers/display/display.h"

#include "../version.h"

#include "patchfinder.h"
#include "kernel.h"
#include "args.h"

#include "mac.h"
#include "shellcode.h"

#define KERNEL_SIZE         0x1200000
#define IBOOT_SIZE          0x48000

uint32_t RDSK_BOOT = 0xdeadfeed;

typedef void (*prepare_and_jump_t)(void* boot, void *ptr, boot_args *arg);

uintptr_t* framebuffer_address;
uintptr_t* base_address;
unsigned int display_width;
unsigned int display_height;

get_env_uint_t _get_env_uint;
get_env_t _get_env;
printf_t _printf;

#define DEBUGLOG(x, ...) do { printf("[DEBUG] "x"", ##__VA_ARGS__); } while(0)
#define FOUND(x, ...) do { printf("[Found] "x"", ##__VA_ARGS__); } while(0)
#define ERROR(x) do { printf("[ERROR] "x""); } while(0)
#define PATCHED(x) do { printf("[PATCHED] "x""); } while(0)

static void print_banner() {
    printf("=======================================\n");
    printf("::\n");
    printf(":: p0insettia payload, Copyright 2021, dora2ios/sakuRdev.\n");
    printf("::\n");
    printf("::\tBUILD_TAG: payload-%d.%d.%d\n", systemVer, majorVer, minorVer);
    printf("::\n");
#ifdef DEBUG
    printf("::\tBUILD_STYLE: DEBUG\n");
#else
    printf("::\tBUILD_STYLE: RELEASE\n");
#endif
    printf("::\n");
    printf("=======================================\n");
    printf("\n");
    printf("preparing to setup the payload...\n");
    printf("---------------------------------------\n");
    printf(":: Credits:\n");
    printf("::  axi0mX\n");
    printf("::  geohot\n");
    printf("::  iH8sn0w\n");
    printf("::  JonathanSeals\n");
    printf("::  planetbeing\n");
    printf("::  posixninja\n");
    printf("::  qwertyoruiopz\n");
    printf("::  synackuk\n");
    printf("::  xerub\n");
    printf("::  checkra1n team\n");
    printf("---------------------------------------\n");
    printf("\n");
}

void wk8(uint32_t addr, uint8_t val){
    *(uint8_t*)addr = val;
}

void wk16(uint32_t addr, uint16_t val){
    *(uint16_t*)addr = val;
}

void wk32(uint32_t addr, uint32_t val){
    *(uint32_t*)addr = val;
}

uint32_t POLICY_OPS(uint32_t addr, uint32_t val){
    if(*(uint32_t*)addr == 0x0){ /* *mpc_ops == 0 -> SKIP */
        return 0;
    }
    
    wk32(addr, val); /* replace with ret0 gadget */
    return 0;
}

/* make_bl - from iloader by xerub */
uint32_t make_bl(int blx, int pos, int tgt)
{
    int delta;
    unsigned short pfx;
    unsigned short sfx;
    unsigned int omask = 0xF800;
    unsigned int amask = 0x7FF;
    if (blx) { /* untested */
        omask = 0xE800;
        amask = 0x7FE;
        pos &= ~3;
    }
    delta = tgt - pos - 4; /* range: 0x400000 */
    pfx = 0xF000 | ((delta >> 12) & 0x7FF);
    sfx =  omask | ((delta >>  1) & amask);
    return (unsigned int)pfx | ((unsigned int)sfx << 16);
}

unsigned int
make_b_w(int pos, int tgt)
{
    int delta;
    unsigned int i;
    unsigned short pfx;
    unsigned short sfx;
    
    unsigned int omask_1k = 0xB800;
    unsigned int omask_2k = 0xB000;
    unsigned int omask_3k = 0x9800;
    unsigned int omask_4k = 0x9000;
    
    unsigned int amask = 0x7FF;
    unsigned int range;
    
    range = 0x400000;
    
    delta = tgt - pos - 4; /* range: 0x400000 */
    i = 0;
    if(tgt > pos) i = tgt - pos - 4;
    if(tgt < pos) i = pos - tgt - 4;
    
    if (i < range){
        pfx = 0xF000 | ((delta >> 12) & 0x7FF);
        sfx =  omask_1k | ((delta >>  1) & amask);
        
        return (unsigned int)pfx | ((unsigned int)sfx << 16);
    }
    
    if (range < i && i < range*2){ /* range: 0x400000-0x800000 */
        delta -= range;
        pfx = 0xF000 | ((delta >> 12) & 0x7FF);
        sfx =  omask_2k | ((delta >>  1) & amask);
        
        return (unsigned int)pfx | ((unsigned int)sfx << 16);
    }
    
    if (range*2 < i && i < range*3){ /* range: 0x800000-0xc000000 */
        delta -= range*2;
        pfx = 0xF000 | ((delta >> 12) & 0x7FF);
        sfx =  omask_3k | ((delta >>  1) & amask);
        
        return (unsigned int)pfx | ((unsigned int)sfx << 16);
    }
    
    if (range*3 < i && i < range*4){ /* range: 0xc00000-0x10000000 */
        delta -= range*3;
        pfx = 0xF000 | ((delta >> 12) & 0x7FF);
        sfx =  omask_4k | ((delta >>  1) & amask);
        return (unsigned int)pfx | ((unsigned int)sfx << 16);
    }
    
    return -1;
}

static void patch_tfp0(uint32_t p, uint32_t c){
    wk16(p, 0xbf00);
    PATCHED("task_for_pid::pid_check patch\n");
    
    wk8(c+1, 0xe0);
    PATCHED("convert_port_to_locked_task patch\n");
}

static void patch_vm_fault_enter(uint32_t addr){
    wk32(addr, 0x0b01f04f);
    PATCHED("vm_fault_enter patch\n");
}

static void patch_vm_map_enter(uint32_t addr){
    wk32(addr, 0xbf00bf00);
    PATCHED("vm_map_enter patch\n");
}

static void patch_vm_map_protect(uint32_t addr){
    wk32(addr, 0xbf00bf00);
    PATCHED("vm_map_protect patch\n");
}

static void patch_csops(uint32_t addr){
    wk32(addr, 0xbf00bf00);
    wk16(addr+4, 0xbf00);
    PATCHED("csops patch\n");
}

static void patch_mount(uint32_t addr){
    wk8((addr+1), 0xe0);
    PATCHED("mount patch\n");
}

static void patch_mount_union(uint32_t addr){
    wk32(addr, 0xbf00bf00);
    wk16(addr+4, 0xbf00);
    PATCHED("union mount patch\n");
}

static void patch_mapForIO(uint32_t addr, uint32_t ptr, uint32_t ret1){
    wk32(addr, 0xbf002000);
    wk32(addr+4, 0xbf00bf00);
    
    wk32(ptr, ret1);
    
    PATCHED("mapForIO patch\n");
}

static void patch_sbcall_debugger(uint32_t addr){
    wk32(addr, 0xbf00bf00);
    PATCHED("sbcall_debugger patch\n");
}

static void patch_amfi_ret(uint32_t addr, uint32_t s, uint32_t kernel_base)
{
    uint32_t unbaseAddr = addr - kernel_base;
    uint32_t unbaseShc = s - kernel_base;
    uint32_t p = make_b_w(unbaseAddr, unbaseShc);
    printf("[AMFI] amfi ret -> shellcode: 0x%08x\n", s+1);
    wk32(addr, p);
}

static void patch_amfi_cred_label_update_execve(uint32_t addr){
    /* set _csEnforcementDisable && _allowEverything
     
     int cred_label_update_execve(...) {
     var_8 = arg9;
     ...
     r23 = var_8;
     ...
     r8 = *(int32_t *)r23;
     if ((r8 & 0x2000) == 0x0) goto loc_2f210;
     ...
     if ((((*(int8_t *)_csEnforcementDisable | *(int8_t *)_allowEverything) & 0xff) == 0x0) || (_PE_i_can_has_debugger.stub() == 0x0)) goto loc_2f1e4;
     ...
     
     loc_2f1e4:
     r8 = *(int32_t *)r23;                           <- SKIP
     if ((r8 & 0x2000000) != 0x0) goto loc_2f204;    <- SKIP
     
     loc_2f204:
     r8 = r8 | 0x2200;
     *(int32_t *)r23 = r8;
     goto loc_2f210;
     
     loc_2f210:
     if ((r8 & 0x8) != 0x0) {
     *(int32_t *)r23 = r8 | 0x800000;
     }
     r0 = loadEntitlementsFromVnode(...);
     ...
     
     }
     
     */
    
    wk32(addr, 0xbf00bf00);
    /* Change only the high byte of the conditional branch to B.n. */
    wk8((addr+4+1), 0xe0);
    printf("[AMFI] amfi_cred_label_update_execve patch\n");
    
}

static void patch_amfi_vnode_check_signature(uint32_t addr){
    /* vnode_check_signature: set _allowEverything */
    wk32(addr, 0xbf00bf00);
    wk32(addr+4, 0xbf00bf00);
    wk32(addr+8, 0xbf00bf00);
    wk32(addr+12, 0xbf00bf00);
    wk32(addr+16, 0xbf00bf00);
    printf("[AMFI] amfi_vnode_check_signature patch\n");
}

static void patch_amfi_loadEntitlementsFromVnode(uint32_t addr){
    /* set _csEnforcementDisable
     *
     * **** iOS 10.2 ****
     *  int loadEntitlementsFromVnode(...) {
     *      if(_csvnode_get_blob.stub() != 0){
     *          loadEntitlementsFromSignature(...);
     *      } else {
     *          if ((*(int8_t *)_csEnforcementDisable == 0) && (_cs_enforcement.stub() != 0x0)) {
     *              *r19 = "no code signature";
     *              return 0;
     *          } else {
     *              if (_PE_i_can_has_debugger.stub() != 0x0) {
     *                  return 1;
     *              } else {
     *                  *r19 = "no code signature";
     *                  return 0;
     *              }
     *          }
     *      }
     *  }
     *
     *  **** iOS 10.3.x ****
     *  int loadEntitlementsFromVnode(...) {
     *      if(_csvnode_get_blob.stub() != 0){
     *          loadEntitlementsFromSignature(...);
     *      } else {
     *          *r19 = "no code signature"; <- NOP
     *          return 0;                   <- return as 1;
     *      }
     *  }
     */
    
    wk32(addr, 0xbf00bf00);
    wk16(addr+4, 0xbf00);
    wk16(addr+6, 0x2001);
    printf("[AMFI] amfi_loadEntitlementsFromVnode patch\n");
}

static void patch_amfi_vnode_check_exec(uint32_t addr){
    /* set _csEnforcementDisable
     *
     * **** iOS 10.2 ****
     *  int _vnode_check_exec(...) {
     *      if ((*(int8_t *)_csEnforcementDisable == 0x0) || (_PE_i_can_has_debugger.stub() == 0x0)) {
     *          if (r19 == 0x0) { // arg7
     *              _Assert.stub();
     *          }
     *          *(int32_t *)r19 = *(int32_t *)r19 | 0x300; // (CS_HARD|CS_KILL)
     *      }
     *      return 0;
     *  }
     *
     *  **** iOS 10.3.x ****
     *  int _vnode_check_exec(...) {
     *      if (csflags == 0) {
     *          _Assert.stub();
     *      }
     *      *csflags |= CS_HARD|CS_KILL; <- NOP
     *      return 0;                    <- always return 0
     *  }
     *
     */

    wk32(addr, 0xbf00bf00);
    wk32(addr+4, 0xbf00bf00);
    wk32(addr+8, 0xbf00bf00);
    printf("[AMFI] amfi_vnode_check_exec patch\n");
}

void loop(void){
    
}

/* The mounted-system boot path can replace iBEC's boot arguments. Set the
 * diagnostic marker in the final boot_args, only after every patch succeeded. */
int lik_mark_jumpstart(boot_args *arg)
{
    const char extra[] = " lik_ios10_jumpstart=1 serial=3 debug=0x14";
    unsigned int len = 0;
    while (len < sizeof(arg->CommandLine) && arg->CommandLine[len]) len++;
    if (len == sizeof(arg->CommandLine)) return 0;
    if (memmem(arg->CommandLine, len, "lik_ios10_jumpstart=1", sizeof("lik_ios10_jumpstart=1") - 1)) return 1;
    if (len + sizeof(extra) > sizeof(arg->CommandLine)) return 0;
    memcpy(arg->CommandLine + len, extra, sizeof(extra));
    return 1;
}

int
_main(void* boot, void *ptr, boot_args *arg)
{
    
    prepare_and_jump_t prepare_and_jump;
    
    uint32_t gPhysBase;
    uint32_t gVirtBase;
    uint32_t slide;
    
    uint32_t i_can_has_debugger;
    uint32_t vfsContextCurrent;
    uint32_t vnodeGetattr;
    uint32_t pid_check;
    uint32_t convert_port_to_locked_task;
    uint32_t mount_off;
    uint32_t mount_union;
    uint32_t vm_map_enter;
    uint32_t vm_map_protect;
    uint32_t csops;
    uint32_t vm_fault_enter;
    uint32_t mapForIO;
    uint32_t kernelConfig_stub;
    uint32_t sb_call_i_can_has_debugger;
    
    uint32_t amfi_execve_ret;
    uint32_t amfi_cred_label_update_execve;
    uint32_t amfi_vnode_check_signature;
    uint32_t amfi_loadEntitlementsFromVnode;
    uint32_t amfi_vnode_check_exec;
    uint32_t sbops;
    
    uint32_t launchd_path;
    
    uint32_t last_text_region;
    
    uint32_t execve;
    uint32_t execve_ptr;
    unsigned char buf[SHC_LEN];
    
    uint32_t ret0_gadget;
    uint32_t ret1_gadget;
    
    base_address = find_base_address();
    _get_env_uint = find_get_env_uint();
    framebuffer_address = find_framebuffer_address();
    _get_env = find_get_env();
    
    _printf = find_printf();
    
    display_width = find_display_width();
    display_height = find_display_height();
    
    prepare_and_jump = (prepare_and_jump_t)find_prepare_and_jump((uint32_t)base_address, IBOOT_SIZE);
    
    drivers_init((uint32_t*)framebuffer_address, display_width, display_height);
    
    print_banner();
    
#ifdef DEBUG
    DEBUGLOG("BASE_ADDRESS: 0x%x\n", base_address);
    DEBUGLOG("GET_ENV_UINT: 0x%x\n", _get_env_uint);
    DEBUGLOG("FRAMEBUFFER: 0x%x\n", framebuffer_address);
    DEBUGLOG("GET_ENV: 0x%x\n", _get_env);
    DEBUGLOG("PRINTF: 0x%x\n", _printf);
    DEBUGLOG("PREPARE_AND_JUMP: 0x%x\n", prepare_and_jump);
#endif
    
    gVirtBase = arg->virtBase;
    gPhysBase = arg->physBase;
    slide = gVirtBase - gPhysBase;
    
#ifdef DEBUG
    FOUND("gVirtBase: 0x%x\n", gVirtBase);
    FOUND("gPhysBase: 0x%x\n", gPhysBase);
    FOUND("KASLR slide: 0x%x\n", slide);
#else
    FOUND("gVirtBase\n");
    FOUND("gPhysBase\n");
#endif
    
    printf("BootArgs: %s\n", arg->CommandLine);
    
    /*** patchfinder:: find sym ***/
    printf("[*] Searching Kernel sym...\n");
    
    i_can_has_debugger = find_PE_i_can_has_debugger(gPhysBase, gVirtBase);
    if(i_can_has_debugger == 0){
        ERROR("Failed to get _PE_i_can_has_debugger\n");
        goto out;
    }
#ifdef DEBUG
    FOUND("_PE_i_can_has_debugger: 0x%x\n", i_can_has_debugger);
#else
    FOUND("_PE_i_can_has_debugger\n");
#endif
    
    
    vfsContextCurrent = find_vfs_context_current(gPhysBase, gVirtBase);
    if(vfsContextCurrent == 0){
        ERROR("Failed to get _vfs_context_current\n");
        goto out;
    }
#ifdef DEBUG
    FOUND("_vfs_context_current: 0x%x\n", vfsContextCurrent);
#else
    FOUND("_vfs_context_current\n");
#endif
    
    
    vnodeGetattr = find_vnode_getattr(gPhysBase, gVirtBase);
    if(vnodeGetattr == 0){
        ERROR("Failed to get _vnode_getattr\n");
        goto out;
    }
#ifdef DEBUG
    FOUND("_vnode_getattr: 0x%x\n", vnodeGetattr);
#else
    FOUND("_vnode_getattr\n");
#endif
    
    
    /*** patchfinder:: find offsets ***/
    printf("[*] Searching Kernel offsets...\n");
    
    pid_check = find_pid_check(gPhysBase, KERNEL_SIZE);
    if(pid_check == 0){
        ERROR("Failed to get pid_check\n");
        goto out;
    }
#ifdef DEBUG
    FOUND("pid_check: 0x%x\n", pid_check);
#else
    FOUND("pid_check\n");
#endif
    
    
    convert_port_to_locked_task = find_convert_port_to_locked_task(gPhysBase, KERNEL_SIZE);
    if(convert_port_to_locked_task == 0){
        ERROR("Failed to get convert_port_to_locked_task\n");
        goto out;
    }
#ifdef DEBUG
    FOUND("convert_port_to_locked_task: 0x%x\n", convert_port_to_locked_task);
#else
    FOUND("convert_port_to_locked_task\n");
#endif
    
    
    mount_off = find_mount_103(gPhysBase, KERNEL_SIZE);
    if(mount_off == 0){
        ERROR("Failed to get mount\n");
        goto out;
    }
#ifdef DEBUG
    FOUND("mount: 0x%x\n", mount_off);
#else
    FOUND("mount\n");
#endif
    
    
    mount_union = find_mount_union(gPhysBase, KERNEL_SIZE);
    if(mount_union == 0){
        ERROR("Failed to get MNT_UNION patch point\n");
        goto out;
    }
#ifdef DEBUG
    FOUND("MNT_UNION patch point: 0x%x\n", mount_union);
#else
    FOUND("MNT_UNION patch point\n");
#endif
    
    
    vm_map_enter = find_vm_map_enter_103(gPhysBase, KERNEL_SIZE);
    if(vm_map_enter == 0){
        ERROR("Failed to get vm_map_enter\n");
        goto out;
    }
#ifdef DEBUG
    FOUND("vm_map_enter: 0x%x\n", vm_map_enter);
#else
    FOUND("vm_map_enter\n");
#endif
    
    
    vm_map_protect = find_vm_map_protect_103(gPhysBase, KERNEL_SIZE);
    if(vm_map_protect == 0){
        ERROR("Failed to get vm_map_protect\n");
        goto out;
    }
#ifdef DEBUG
    FOUND("vm_map_protect: 0x%x\n", vm_map_protect);
#else
    FOUND("vm_map_protect\n");
#endif
    
    csops = find_csops_103(gPhysBase, KERNEL_SIZE);
    if(csops == 0){
        ERROR("Failed to get csops\n");
        goto out;
    }
#ifdef DEBUG
    FOUND("csops: 0x%x\n", csops);
#else
    FOUND("csops\n");
#endif
    
    
    vm_fault_enter = find_vm_fault_enter_103(gPhysBase, KERNEL_SIZE);
    if(vm_fault_enter == 0){
        ERROR("Failed to get vm_fault_enter\n");
        goto out;
    }
#ifdef DEBUG
    FOUND("vm_fault_enter: 0x%x\n", vm_fault_enter);
#else
    FOUND("vm_fault_enter\n");
#endif
    
     
    mapForIO = find_mapForIO_103(gPhysBase, KERNEL_SIZE);
    if(mapForIO == 0){
        ERROR("Failed to get mapForIO\n");
        goto out;
    }
#ifdef DEBUG
    FOUND("mapForIO: 0x%x\n", mapForIO);
#else
    FOUND("mapForIO\n");
#endif
    
    
    kernelConfig_stub = find_lwvm_i_can_has_krnl_conf_stub(gPhysBase, KERNEL_SIZE);
    if(kernelConfig_stub == 0){
        ERROR("Failed to get LwVM::kernelConfig_stub\n");
        goto out;
    }
#ifdef DEBUG
    FOUND("LwVM::kernelConfig_stub: 0x%x\n", kernelConfig_stub);
#else
    FOUND("LwVM::kernelConfig_stub\n");
#endif
    
    
    sb_call_i_can_has_debugger = find_sandbox_call_i_can_has_debugger_103(gPhysBase, KERNEL_SIZE);
    if(sb_call_i_can_has_debugger == 0){
        ERROR("Failed to get sb_call_i_can_has_debugger\n");
        goto out;
    }
#ifdef DEBUG
    FOUND("sb_call_i_can_has_debugger: 0x%x\n", sb_call_i_can_has_debugger);
#else
    FOUND("sb_call_i_can_has_debugger\n");
#endif
    
    
    amfi_execve_ret = find_amfi_execve_ret(gPhysBase, KERNEL_SIZE);
    if(amfi_execve_ret == 0){
        ERROR("Failed to get amfi_execve_ret\n");
        goto out;
    }
#ifdef DEBUG
    FOUND("amfi_execve_ret: 0x%x\n", amfi_execve_ret);
#else
    FOUND("amfi_execve_ret\n");
#endif
    
    
    amfi_cred_label_update_execve = find_amfi_cred_label_update_execve(gPhysBase, KERNEL_SIZE);
    if(amfi_cred_label_update_execve == 0){
        ERROR("Failed to get amfi_cred_label_update_execve\n");
        goto out;
    }
#ifdef DEBUG
    FOUND("amfi_cred_label_update_execve: 0x%x\n", amfi_cred_label_update_execve);
#else
    FOUND("amfi_cred_label_update_execve\n");
#endif
    
    
    amfi_vnode_check_signature = find_amfi_vnode_check_signature(gPhysBase, KERNEL_SIZE);
    if(amfi_vnode_check_signature == 0){
        ERROR("Failed to get amfi_vnode_check_signature\n");
        goto out;
    }
#ifdef DEBUG
    FOUND("amfi_vnode_check_signature: 0x%x\n", amfi_vnode_check_signature);
#else
    FOUND("amfi_vnode_check_signature\n");
#endif
    
    
    amfi_loadEntitlementsFromVnode = find_amfi_loadEntitlementsFromVnode(gPhysBase, KERNEL_SIZE);
    if(amfi_loadEntitlementsFromVnode == 0){
        ERROR("Failed to get amfi_loadEntitlementsFromVnode\n");
        goto out;
    }
#ifdef DEBUG
    FOUND("amfi_loadEntitlementsFromVnode: 0x%x\n", amfi_loadEntitlementsFromVnode);
#else
    FOUND("amfi_loadEntitlementsFromVnode\n");
#endif
    
    
    amfi_vnode_check_exec = find_amfi_vnode_check_exec(gPhysBase, KERNEL_SIZE);
    if(amfi_vnode_check_exec == 0){
        ERROR("Failed to get amfi_vnode_check_exec\n");
        goto out;
    }
#ifdef DEBUG
    FOUND("amfi_vnode_check_exec: 0x%x\n", amfi_vnode_check_exec);
#else
    FOUND("amfi_vnode_check_exec\n");
#endif
    
    sbops = (uint32_t)find_sbops(gPhysBase, KERNEL_SIZE);
    if(!sbops){
        ERROR("Failed to get sbops\n");
        goto out;
    }
#ifdef DEBUG
    FOUND("sbops: 0x%x\n", sbops);
#else
    FOUND("sbops\n");
#endif
    
    
    launchd_path = find_launchd(gPhysBase, KERNEL_SIZE);
    if(!launchd_path){
        ERROR("Failed to get launchd path\n");
        goto out;
    }
#ifdef DEBUG
    FOUND("launchd: 0x%x\n", launchd_path);
#else
    FOUND("launchd\n");
#endif
    
    
    last_text_region = (uint32_t)find_last_text_region(gPhysBase);
    if(!last_text_region){
        ERROR("Failed to get last _TEXT region\n");
        goto out;
    }
#ifdef DEBUG
    FOUND("last _TEXT region: 0x%x\n", last_text_region);
#else
    FOUND("last _TEXT region\n");
#endif
    
    last_text_region -= slide; /* unslide */
    
    
    /* setup */
    execve = sbops+offsetof(struct mac_policy_ops, mpo_cred_label_update_execve);
    execve_ptr = *(uint32_t*)execve;
    if(!execve_ptr){
        ERROR("Failed to get sandbox mpo_cred_label_update_execve\n");
        goto out;
    }
#ifdef DEBUG
    FOUND("mpo_cred_label_update_execve: 0x%08x\n", execve_ptr);
#else
    FOUND("mpo_cred_label_update_execve\n");
#endif
    
    
    /* setup: shellcode */
    memcpy(buf, shc_bin, SHC_LEN);
    *(uint32_t*)(buf+0x019c) = vfsContextCurrent + 1 + slide;
    *(uint32_t*)(buf+0x01a0) = vnodeGetattr + 1 + slide;
    *(uint32_t*)(buf+0x01a4) = execve_ptr + slide;
    
    memcpy((void*)last_text_region, buf, SHC_LEN);
    
    ret0_gadget = last_text_region + 0x1A8 + 1;
    ret1_gadget = last_text_region + 0x1AC + 1;
#ifdef DEBUG
    printf("[Setup] shellcode: 0x%08x\n", last_text_region);
    printf("[Setup] ret0_gadget: 0x%08x\n", ret0_gadget);
    printf("[Setup] ret1_gadget: 0x%08x\n", ret1_gadget);
#else
    printf("[Setup] shellcode\n");
#endif
    
    wk32(execve, (last_text_region+4) + 1);
#ifdef DEBUG
    printf("[Hook] sandbox mpo_cred_label_update_execve: 0x%08x\n", (last_text_region+4) + 1);
#else
    printf("[Hook] sandbox mpo_cred_label_update_execve\n");
#endif
    
    
    /* kpatch */
    printf("[*] patching kernel...\n");
    patch_tfp0(pid_check, convert_port_to_locked_task);
    
    patch_vm_fault_enter(vm_fault_enter);
    patch_vm_map_enter(vm_map_enter);
    patch_vm_map_protect(vm_map_protect);
    patch_csops(csops);
    patch_mount(mount_off);
    patch_mount_union(mount_union);
    patch_mapForIO(mapForIO, kernelConfig_stub, ret1_gadget);
    patch_sbcall_debugger(sb_call_i_can_has_debugger);
    
    {
        POLICY_OPS(sbops+offsetof(struct mac_policy_ops, mpo_mount_check_mount), ret0_gadget);
        POLICY_OPS(sbops+offsetof(struct mac_policy_ops, mpo_mount_check_remount), ret0_gadget);
        POLICY_OPS(sbops+offsetof(struct mac_policy_ops, mpo_mount_check_umount), ret0_gadget);
        POLICY_OPS(sbops+offsetof(struct mac_policy_ops, mpo_vnode_check_write), ret0_gadget);
        
        POLICY_OPS(sbops+offsetof(struct mac_policy_ops, mpo_file_check_mmap), ret0_gadget);
        POLICY_OPS(sbops+offsetof(struct mac_policy_ops, mpo_vnode_check_rename), ret0_gadget);
        POLICY_OPS(sbops+offsetof(struct mac_policy_ops, mpo_vnode_check_access), ret0_gadget);
        POLICY_OPS(sbops+offsetof(struct mac_policy_ops, mpo_vnode_check_chroot), ret0_gadget);
        POLICY_OPS(sbops+offsetof(struct mac_policy_ops, mpo_vnode_check_create), ret0_gadget);
        POLICY_OPS(sbops+offsetof(struct mac_policy_ops, mpo_vnode_check_deleteextattr), ret0_gadget);
        POLICY_OPS(sbops+offsetof(struct mac_policy_ops, mpo_vnode_check_exchangedata), ret0_gadget);
        POLICY_OPS(sbops+offsetof(struct mac_policy_ops, mpo_vnode_check_exec), ret0_gadget);
        POLICY_OPS(sbops+offsetof(struct mac_policy_ops, mpo_vnode_check_getattrlist), ret0_gadget);
        POLICY_OPS(sbops+offsetof(struct mac_policy_ops, mpo_vnode_check_getextattr), ret0_gadget);
        POLICY_OPS(sbops+offsetof(struct mac_policy_ops, mpo_vnode_check_ioctl), ret0_gadget);
        POLICY_OPS(sbops+offsetof(struct mac_policy_ops, mpo_vnode_check_link), ret0_gadget);
        POLICY_OPS(sbops+offsetof(struct mac_policy_ops, mpo_vnode_check_listextattr), ret0_gadget);
        POLICY_OPS(sbops+offsetof(struct mac_policy_ops, mpo_vnode_check_open), ret0_gadget);
        POLICY_OPS(sbops+offsetof(struct mac_policy_ops, mpo_vnode_check_readlink), ret0_gadget);
        POLICY_OPS(sbops+offsetof(struct mac_policy_ops, mpo_vnode_check_setattrlist), ret0_gadget);
        POLICY_OPS(sbops+offsetof(struct mac_policy_ops, mpo_vnode_check_setextattr), ret0_gadget);
        POLICY_OPS(sbops+offsetof(struct mac_policy_ops, mpo_vnode_check_setflags), ret0_gadget);
        POLICY_OPS(sbops+offsetof(struct mac_policy_ops, mpo_vnode_check_setmode), ret0_gadget);
        POLICY_OPS(sbops+offsetof(struct mac_policy_ops, mpo_vnode_check_setowner), ret0_gadget);
        POLICY_OPS(sbops+offsetof(struct mac_policy_ops, mpo_vnode_check_setutimes), ret0_gadget);
        POLICY_OPS(sbops+offsetof(struct mac_policy_ops, mpo_vnode_check_stat), ret0_gadget);
        POLICY_OPS(sbops+offsetof(struct mac_policy_ops, mpo_vnode_check_truncate), ret0_gadget);
        POLICY_OPS(sbops+offsetof(struct mac_policy_ops, mpo_vnode_check_unlink), ret0_gadget);
        POLICY_OPS(sbops+offsetof(struct mac_policy_ops, mpo_vnode_notify_create), ret0_gadget);
        POLICY_OPS(sbops+offsetof(struct mac_policy_ops, mpo_vnode_check_fsgetpath), ret0_gadget);
        POLICY_OPS(sbops+offsetof(struct mac_policy_ops, mpo_vnode_check_getattr), ret0_gadget);
        POLICY_OPS(sbops+offsetof(struct mac_policy_ops, mpo_mount_check_stat), ret0_gadget);
        POLICY_OPS(sbops+offsetof(struct mac_policy_ops, mpo_proc_check_setauid), ret0_gadget);
        POLICY_OPS(sbops+offsetof(struct mac_policy_ops, mpo_proc_check_getauid), ret0_gadget);
        
        POLICY_OPS(sbops+offsetof(struct mac_policy_ops, mpo_proc_check_fork), ret0_gadget);
        
        POLICY_OPS(sbops+offsetof(struct mac_policy_ops, mpo_proc_check_get_cs_info), ret0_gadget);
        POLICY_OPS(sbops+offsetof(struct mac_policy_ops, mpo_proc_check_set_cs_info), ret0_gadget);
        
        PATCHED("sbops\n");
        
    }
    
    {
        printf("[AMFI] patching amfi\n");
        patch_amfi_ret(amfi_execve_ret, last_text_region, gPhysBase+0x1000);
        patch_amfi_cred_label_update_execve(amfi_cred_label_update_execve);
        patch_amfi_vnode_check_signature(amfi_vnode_check_signature);
        patch_amfi_loadEntitlementsFromVnode(amfi_loadEntitlementsFromVnode);
        patch_amfi_vnode_check_exec(amfi_vnode_check_exec);
        wk32(i_can_has_debugger, 0x47702001);
        printf("[AMFI] done!\n");
        
    }
    
    if(RDSK_BOOT == 0){
        wk32(launchd_path+1, 0x78786168);
        PATCHED("launchd\n");
    }
    
    
    if (!lik_mark_jumpstart(arg)) {
        ERROR("Boot arguments are too long for the jump-start marker\n");
        goto out;
    }

    printf("[*] Done!\n");
    
    printf("Booting...\n");
    printf("\n");
    
    prepare_and_jump(boot, ptr, arg);
    return 0;
    
out:
    ERROR("Failed to boot!\n");
loop:
    loop();
    goto loop;
    
    return 0;
}
