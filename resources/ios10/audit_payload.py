#!/usr/bin/env python3
"""Exercise compiled ARM patchfinders against supplied firmware, without USB.

Developer check: requires Unicorn 2.x and arm-none-eabi-nm. This emulates finder
functions, not an iPhone boot or the complete kernel patch sequence. Hardware
and boot-time address mapping still require a real-device test.
"""

import argparse
import hashlib
import json
from pathlib import Path
import struct
import subprocess

from macho import ImageError, commands, unpack, checked


def symbols(nm, elf):
    result = {}
    for line in subprocess.check_output([nm, "-g", str(elf)], text=True).splitlines():
        fields = line.split()
        if len(fields) == 3 and fields[1] in ("T", "B", "D"):
            result[fields[2]] = int(fields[0], 16)
    return result


def emulator(payload, kernel, ibec):
    from unicorn import Uc, UC_ARCH_ARM, UC_MODE_ARM
    emu = Uc(UC_ARCH_ARM, UC_MODE_ARM)
    emu.mem_map(0, 0x100000)
    emu.mem_write(0, payload)
    emu.mem_map(0x40000000, 0x100000)  # stack
    emu.mem_map(0x60000000, 0x1000)  # return sentinel
    emu.mem_map(0x80000000, 0x2000000)
    emu.mem_map(0xBFF00000, 0x100000)
    emu.mem_write(0xBFF00000, ibec)
    for cmd, pos, size in commands(kernel):
        if cmd != 1:
            continue
        vmaddr, vmsize, fileoff, filesize = unpack("<4I", kernel, pos + 24)
        if filesize > vmsize or vmaddr < 0x80000000 or vmaddr + vmsize > 0x82000000:
            raise ImageError("Kernel segment is outside the audit's A6 mapping")
        if filesize:
            emu.mem_write(vmaddr, checked(kernel, fileoff, filesize))
    return emu


def invoke(emu, address, arg0, arg1):
    from unicorn.arm_const import UC_ARM_REG_R0, UC_ARM_REG_R1, UC_ARM_REG_LR, UC_ARM_REG_SP, UC_ARM_REG_PC
    emu.reg_write(UC_ARM_REG_SP, 0x400F0000)
    emu.reg_write(UC_ARM_REG_R0, arg0)
    emu.reg_write(UC_ARM_REG_R1, arg1)
    emu.reg_write(UC_ARM_REG_LR, 0x60000000)
    emu.emu_start(address, 0x60000000, timeout=10_000_000, count=200_000_000)
    if emu.reg_read(UC_ARM_REG_PC) != 0x60000000:
        raise ImageError("Finder timed out or exceeded its instruction budget")
    return emu.reg_read(UC_ARM_REG_R0)


def audit(args):
    source = Path(__file__).resolve().parent / "payload-src"
    kernel, ibec = args.kernel.read_bytes(), args.ibec.read_bytes()
    hook = source / "hook"
    prehook = source / "prehook"
    report = {"kernel_sha256": hashlib.sha256(kernel).hexdigest(),
              "ibec_sha256": hashlib.sha256(ibec).hexdigest(), "finders": {},
              "hardware_tested": False,
              "scope": "Compiled ARM finder routines, linked-address execution; not a complete boot simulation"}
    tests = [("find_" + name, 0x80000000, 0x1200000) for name in (
        "pid_check", "convert_port_to_locked_task", "mount_103", "mount_union", "vm_map_enter_103",
        "vm_map_protect_103", "csops_103", "vm_fault_enter_103", "mapForIO_103",
        "lwvm_i_can_has_krnl_conf_stub", "sandbox_call_i_can_has_debugger_103", "amfi_execve_ret",
        "amfi_cred_label_update_execve", "amfi_vnode_check_signature", "amfi_loadEntitlementsFromVnode",
        "amfi_vnode_check_exec", "launchd", "sbops")]
    tests += [("find_" + name, 0x80000000, 0x80000000) for name in (
        "PE_i_can_has_debugger", "vfs_context_current", "vnode_getattr", "last_text_region")]
    tests += [("find_prepare_and_jump", 0xBFF00000, 0x48000)]
    for directory, items in ((hook, tests), (prehook, [("find_" + name, 0xBFF00000, 0x48000)
                                                     for name in ("dt_load", "mount_and_boot_system", "hook_point")])):
        blob = (directory / "payload").read_bytes()
        table = symbols(args.nm, directory / "payload.elf")
        emu = emulator(blob, kernel, ibec)
        before = hashlib.sha256(bytes(emu.mem_read(0x80000000, 0x2000000))).digest()
        for name, a, b in items:
            value = invoke(emu, table[name], a, b)
            if not a <= value < a + (0x100000 if a == 0xBFF00000 else 0x2000000):
                raise ImageError(name + " did not resolve inside the expected firmware mapping")
            report["finders"][name] = f"0x{value:08x}"
            print(name + ": " + report["finders"][name], flush=True)
        after = hashlib.sha256(bytes(emu.mem_read(0x80000000, 0x2000000))).digest()
        if before != after:
            raise ImageError("A read-only finder unexpectedly changed the kernel image")
        report[directory.name + "_sha256"] = hashlib.sha256(blob).hexdigest()
    args.report.write_text(json.dumps(report, indent=2) + "\n")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--kernel", type=Path, required=True)
    parser.add_argument("--ibec", type=Path, required=True)
    parser.add_argument("--nm", required=True)
    parser.add_argument("--report", type=Path, required=True)
    audit(parser.parse_args())
