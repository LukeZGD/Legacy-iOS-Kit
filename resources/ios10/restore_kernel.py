"""Offline AMFI adjustment for the temporary iOS 10 restore kernel.

This implementation follows Procyon's find_amfi_vnode_check_signature and
untether/src/patches.js at e30a352f59756452befb4f6303a996bf4650eb12 (MIT).
Resolve the AMFI error string, walk back to its function prologue, then locate
the nine-halfword check and the following conditional branch in that function.
Procyon also replaces these ten halfwords with NOPs. No p0insettia payload or
runtime code is used. This affects the restore ramdisk kernel ONLY.
"""

import hashlib
import struct

from macho import ImageError, checked, code_range, commands, find_string_setup, unpack

IDENTIFIER = b"com.apple.driver.AppleMobileFileIntegrity\0"
MESSAGE = b"The signature could not be validated because AMFI could not load its entitlements for validation: %s"
MASK = ((0xFF00, 0x4600), (0xF800, 0xF000), (0xD000, 0xD000),
        (0xFF00, 0x4600), (0xFD00, 0xB100), (0xFF00, 0x4600),
        (0xF800, 0xF000), (0xD000, 0xD000), (0xF80F, 0x2801))


def segments(data):
    result = []
    for cmd, pos, size in commands(data):
        if cmd != 1:
            continue
        if size < 56:
            raise ImageError("Truncated kernel segment")
        name, vm, vmsize, off, length = unpack("<16s4I", data, pos + 8)
        checked(data, off, length)
        if length > vmsize:
            raise ImageError("Kernel segment file size exceeds its virtual size")
        result.append((name.rstrip(b"\0"), vm, vmsize, off, length))
    return result


def amfi_image(kernel):
    ranges = [s for s in segments(kernel) if s[0] == b"__PRELINK_TEXT"]
    if len(ranges) != 1:
        raise ImageError("Expected one prelinked kernel text segment")
    _, vm, _, off, length = ranges[0]
    end = off + length
    identity = kernel.find(IDENTIFIER, off, end)
    if identity < 0 or kernel.find(IDENTIFIER, identity + 1, end) >= 0:
        raise ImageError("AMFI identifier is missing or ambiguous")
    start = kernel.rfind(struct.pack("<I", 0xFEEDFACE), off, identity)
    if start < off:
        raise ImageError("AMFI Mach-O header not found")
    entries = segments(kernel[start:end])
    text = [s for s in entries if s[0] == b"__TEXT"]
    data = [s for s in entries if s[0] == b"__DATA"]
    if (len(text) != 1 or len(data) != 1 or text[0][3] != 0
            or text[0][1] != vm + start - off):
        raise ImageError("Unexpected AMFI Mach-O mapping")
    if not start + data[0][3] <= identity < start + data[0][3] + data[0][4]:
        raise ImageError("AMFI identifier is outside its module data")
    size = max(s[3] + s[4] for s in entries)
    image = checked(kernel, start, size)
    if start + size > end:
        raise ImageError("AMFI extends beyond prelinked text")
    return start, text[0][1], image


def patch_restore_kernel(original):
    start, vm, image = amfi_image(original)
    lo, hi = code_range(image)
    reference = find_string_setup(image, (lo, hi), MESSAGE)
    # Procyon's preamble finder accepts Thumb PUSH with LR, or PUSH.W.
    preambles=[]
    for off in range(max(lo,reference-2048),reference,2):
        half=unpack("<H",image,off)[0]
        if half & 0xff00 == 0xb500 or half == 0xe92d and unpack("<H",image,off+2)[0] & 0x4000:
            preambles.append(off)
    if not preambles:raise ImageError("Restore AMFI function prologue missing")
    function_start=preambles[-1]
    found=[]
    for pos in range(function_start,reference-18,2):
        if all(unpack("<H",image,pos+i*2)[0]&mask==value for i,(mask,value) in enumerate(MASK)):
            if unpack("<H",image,pos+18)[0]&0xff00 != 0xd100:
                raise ImageError("Unexpected AMFI conditional branch")
            found.append(pos)
    if len(found)!=1:raise ImageError("Restore AMFI check is missing or ambiguous within its function")
    pos=found[0]
    if not pos+20<=reference<pos+256:raise ImageError("AMFI error path is outside the expected function layout")
    replacement = b"\x00\xbf" * 10
    result = bytearray(original)
    result[start + pos:start + pos + 20] = replacement
    return bytes(result), {
        "method": "Procyon AMFI finder and ten-halfword patch",
        "source_commit": "e30a352f59756452befb4f6303a996bf4650eb12",
        "function_start": vm+function_start,
        "scope": "temporary RestoreKernelCache only",
        "file_offset": start + pos,
        "virtual_address": vm + pos,
        "message_reference": vm + reference,
        "before": image[pos:pos + 20].hex(),
        "after": replacement.hex(),
        "input_sha256": hashlib.sha256(original).hexdigest(),
        "output_sha256": hashlib.sha256(result).hexdigest(),
        "hardware_tested": False,
    }


def prepare_restore_kernel(runner, source, output):
    raw = output.with_suffix(".raw")
    patched = output.with_suffix(".patched")
    roundtrip = output.with_suffix(".roundtrip")
    runner.run("xpwntool", source, raw)
    data, audit = patch_restore_kernel(raw.read_bytes())
    patched.write_bytes(data)
    runner.run("xpwntool", patched, output, "-t", source)
    runner.run("xpwntool", output, roundtrip)
    if roundtrip.read_bytes() != data:
        raise ImageError("Restore kernel container round trip failed")
    return audit
