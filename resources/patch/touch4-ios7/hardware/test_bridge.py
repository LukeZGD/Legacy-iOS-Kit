# SPDX-License-Identifier: GPL-3.0-or-later
"""Emulate the actual Thumb bridge and original constructor continuation."""
from pathlib import Path
import sys, json, struct
from unicorn import Uc, UC_ARCH_ARM, UC_MODE_THUMB, UC_HOOK_CODE
from unicorn.arm_const import *

import argparse
from macho import MachO
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('kernel', type=Path, help='Built kernel.n81.macho')
args = parser.parse_args()
bridge = json.loads(Path(__file__).with_name('bridge.json').read_text())
base = int(bridge['hook_address'], 16)
entry = int(bridge['entry'], 16)
normal = int(bridge['resume_normal'], 16)
done = int(bridge['resume_fail'], 16)
kernel = MachO(args.kernel)
stub = kernel.b[kernel.offset(base):kernel.offset(base) + len(bytes.fromhex(bridge['hook_bytes']))]
assert stub == bytes.fromhex(bridge['hook_bytes'])
tail = kernel.b[kernel.offset(normal):kernel.offset(done)]
old = stub[bridge['old_config_offset']:bridge['new_config_offset']]
new = stub[bridge['new_config_offset']:]
GET_BYTES, SET_CONFIG = 0x1000200, 0x1000300
DEVICE, DATA, TABLE, BYTES = 0x1000400, 0x1000600, 0x1001000, 0x1002000
SP = 0x3000ff0

def run(length, data, slide, expected, setter_result=0):
    u = Uc(UC_ARCH_ARM, UC_MODE_THUMB)
    u.mem_map(0x1000000, 0x4000)
    u.mem_map(0x3000000, 0x2000)
    u.mem_map((entry + slide) & ~0xfff, 0x1000)
    u.mem_map((base + slide) & ~0xfff, 0x1000)
    u.mem_write(base + slide, stub)
    u.mem_write(normal + slide, tail)
    u.mem_write(GET_BYTES, b'\x70\x47')
    u.mem_write(SET_CONFIG, b'\x70\x47')
    u.mem_write(DEVICE, struct.pack('<I', TABLE))
    u.mem_write(DATA, struct.pack('<I', TABLE))
    u.mem_write(TABLE + 0x68, struct.pack('<I', GET_BYTES | 1))
    u.mem_write(TABLE + 0x34c, struct.pack('<I', SET_CONFIG | 1))
    u.mem_write(BYTES, bytes(data))
    for register, value in [(UC_ARM_REG_R0, length), (UC_ARM_REG_R4, DEVICE),
                            (UC_ARM_REG_R5, 0x55555555), (UC_ARM_REG_R6, DATA),
                            (UC_ARM_REG_R7, 0x77777777), (UC_ARM_REG_R8, 0x88888888),
                            (UC_ARM_REG_SP, SP)]:
        u.reg_write(register, value)
    calls = []
    reached = []
    def observe(emulator, address, size, _):
        if address == GET_BYTES:
            assert emulator.reg_read(UC_ARM_REG_R0) == DATA
            emulator.reg_write(UC_ARM_REG_R0, BYTES)
        elif address == SET_CONFIG:
            assert emulator.reg_read(UC_ARM_REG_R0) == DEVICE
            pointer = emulator.reg_read(UC_ARM_REG_R1)
            calls.append(bytes(emulator.mem_read(pointer, 36)))
            emulator.reg_write(UC_ARM_REG_R0, setter_result)
        elif address == done + slide:
            reached.append(address)
            emulator.emu_stop()
    u.hook_add(UC_HOOK_CODE, observe)
    u.emu_start((base + slide) | 1, done + slide + 2, count=1000)
    assert reached, 'Bridge did not reach the original epilogue'
    assert calls == ([] if expected is None else [expected])
    assert u.reg_read(UC_ARM_REG_R5) == (1 if expected is not None and setter_result == 0 else 0)
    for register, value in [(UC_ARM_REG_R4, DEVICE), (UC_ARM_REG_R6, DATA),
                            (UC_ARM_REG_R7, 0x77777777), (UC_ARM_REG_SP, SP)]:
        assert u.reg_read(register) == value, (register, u.reg_read(register), value)

cases = []
for slide in [0, 0x04800000, 0x10200000]:
    run(32, old, slide, new); cases.append(['legacy conversion', hex(slide)])
    run(32, old, slide, new, setter_result=0xe00002c2); cases.append(['setter failure', hex(slide)])
    for word in range(8):
        bad = bytearray(old); bad[word * 4] ^= 1
        run(32, bad, slide, None); cases.append(['reject mismatch', word, hex(slide)])
    for length in [0, 16, 31, 33, 35]:
        run(length, new, slide, None); cases.append(['reject short', length, hex(slide)])
    for length in [36, 40]:
        run(length, new + bytes(4), slide, new); cases.append(['original >=36 path', length, hex(slide)])
print(json.dumps({'result': 'passed', 'cases': len(cases), 'slides': ['0', '0x04800000', '0x10200000']}))
