"""Bounded 32-bit Mach-O and Thumb helpers for offline iOS 10 preparation.

The ASR string-reference method follows powdersn0w_pub's xpwn/common/patchfinder.c
and xpwn/asr/asr.c (dora2ios, planetbeing and contributors), GPL-3.0.
No device or host service is accessed by this module.
"""

import hashlib
import struct


class ImageError(ValueError):
    pass


def checked(data, offset, size):
    if offset < 0 or size < 0 or offset + size > len(data):
        raise ImageError("Image structure extends outside the file")
    return data[offset:offset + size]


def unpack(fmt, data, offset):
    return struct.unpack(fmt, checked(data, offset, struct.calcsize(fmt)))


def commands(data):
    magic, cpu, _, _, count, length, _ = unpack("<7I", data, 0)
    if magic != 0xFEEDFACE or cpu != 12:
        raise ImageError("Expected a thin, little-endian ARM Mach-O")
    checked(data, 28, length)
    pos, end = 28, 28 + length
    for _ in range(count):
        cmd, size = unpack("<II", data, pos)
        if size < 8 or size % 4 or pos + size > end:
            raise ImageError("Invalid Mach-O load command")
        yield cmd, pos, size
        pos += size
    if pos != end:
        raise ImageError("Mach-O command count/size mismatch")


def code_range(data):
    matches = []
    for cmd, pos, size in commands(data):
        if cmd != 1:
            continue
        name, vm, vmsize, fileoff, filesize, _, _, count, _ = unpack(
            "<16s8I", data, pos + 8)
        if size != 56 + count * 68:
            raise ImageError("Invalid segment section table")
        if name.rstrip(b"\0") != b"__TEXT":
            continue
        for i in range(count):
            section = pos + 56 + i * 68
            secname, segname, addr, nbytes, off = unpack("<16s16sIII", data, section)
            if secname.rstrip(b"\0") == b"__text":
                if addr - vm != off - fileoff or off + nbytes > fileoff + filesize:
                    raise ImageError("Unsupported ASR section mapping")
                checked(data, off, nbytes)
                matches.append((off, off + nbytes))
    if len(matches) != 1:
        raise ImageError("Expected one executable __TEXT,__text section")
    return matches[0]


def code_directories(data):
    sigs = [(pos, size) for cmd, pos, size in commands(data) if cmd == 0x1D]
    if len(sigs) != 1 or sigs[0][1] != 16:
        raise ImageError("Expected one Mach-O code signature")
    sigoff, sigsize = unpack("<II", data, sigs[0][0] + 8)
    sig = checked(data, sigoff, sigsize)
    magic, size, count = unpack(">III", sig, 0)
    if magic != 0xFADE0CC0 or size > len(sig) or count > (size - 12) // 8:
        raise ImageError("Invalid code-signature superblob")
    sig = sig[:size]
    result = []
    for i in range(count):
        slot, off = unpack(">II", sig, 12 + i * 8)
        if off < 12 + count * 8:
            raise ImageError("Code-signature blob overlaps its index")
        magic, length = unpack(">II", sig, off)
        blob = checked(sig, off, length)
        if slot != 0 and not 0x1000 <= slot <= 0x1005:
            continue
        if magic != 0xFADE0C02 or length < 44:
            raise ImageError("Invalid CodeDirectory")
        _, _, version, _, hash_off, _, specials, slots, limit = unpack(">9I", blob, 0)
        hash_size, hash_type, _, page_exp = unpack("4B", blob, 36)
        algorithms = {1: ("sha1", 20), 2: ("sha256", 32), 3: ("sha256", 20)}
        if hash_type not in algorithms or hash_size != algorithms[hash_type][1]:
            raise ImageError("Unsupported CodeDirectory hash algorithm")
        if not 9 <= page_exp <= 16 or limit != sigoff:
            raise ImageError("Unsupported CodeDirectory page size or code limit")
        if version >= 0x20100 and unpack(">I", blob, 44)[0]:
            raise ImageError("Scattered CodeDirectories are unsupported")
        page = 1 << page_exp
        if slots != (limit + page - 1) // page:
            raise ImageError("CodeDirectory slot count does not cover the executable")
        if hash_off < specials * hash_size + 44:
            raise ImageError("Invalid CodeDirectory special-slot range")
        checked(blob, hash_off - specials * hash_size, (slots + specials) * hash_size)
        result.append(dict(offset=sigoff + off, hash_offset=hash_off,
                           hash_size=hash_size, algorithm=algorithms[hash_type][0],
                           slots=slots, page=page, limit=limit))
    if not result:
        raise ImageError("Missing CodeDirectory")
    return result


def check_or_update_hashes(data, update=False):
    """Verify original hashes, or repair code slots after changing instructions.

    This is not an Apple signature: patched restore components require pwned DFU.
    Special slots and the CMS blob are preserved, as in the upstream ASR patcher.
    """
    directories = code_directories(data)
    for cd in directories:
        for slot in range(cd["slots"]):
            start = slot * cd["page"]
            digest = hashlib.new(cd["algorithm"], data[start:min(
                start + cd["page"], cd["limit"])]).digest()[:cd["hash_size"]]
            pos = cd["offset"] + cd["hash_offset"] + slot * cd["hash_size"]
            if update:
                data[pos:pos + len(digest)] = digest
            elif checked(data, pos, len(digest)) != digest:
                raise ImageError("Original executable code hash does not match")
    return directories


def is_wide(h):
    return h & 0xE000 == 0xE000 and h & 0x1800 != 0


def mov_immediate(a, b):
    if a & 0xF800 == 0x2000:
        return (a >> 8) & 7, a & 0xFF
    if b & 0x8000:
        return None
    if a & 0xFBF0 == 0xF240:
        return (b >> 8) & 15, (a & 15) << 12 | (a & 0x400) << 1 | (b & 0x7000) >> 4 | b & 255
    if a & 0xFBEF == 0xF04F:
        imm = (a & 0x400) << 1 | (b & 0x7000) >> 4 | b & 255
        if imm < 0x400:
            low = imm & 255
            value = (low, low << 16 | low, low << 24 | low << 8,
                     low * 0x01010101)[imm >> 8]
        else:
            low, shift = 0x80 | imm & 0x7F, imm >> 7
            value = ((low >> shift) | (low << (32 - shift))) & 0xFFFFFFFF
        return (b >> 8) & 15, value
    return None


def find_string_setup(data, text, string):
    """Locate the instruction sequence forming a PC-relative string address.

    Bounded variant of the upstream Thumb reference finder. Limit it to the
    executable section and reject missing or ambiguous matches.
    """
    target = data.find(string + b"\0")
    if target < 0 or data.find(string + b"\0", target + 1) >= 0:
        raise ImageError("Expected one ASR verification message")
    values, starts = [None] * 16, [None] * 16
    matches = []
    pos, end = text
    while pos + 2 <= end:
        a = unpack("<H", data, pos)[0]
        b = unpack("<H", data, pos + 2)[0] if pos + 4 <= end else 0x8000
        width = 4 if is_wide(a) else 2
        if pos + width > end:
            raise ImageError("Truncated Thumb instruction")
        mov = mov_immediate(a, b)
        if mov:
            reg, value = mov
            values[reg], starts[reg] = value, pos
        elif a & 0xF800 == 0x4800 or a & 0xFF7F == 0xF85F:
            if a & 0xF800 == 0x4800:
                reg, delta = a >> 8 & 7, (a & 255) << 2
            else:
                reg, delta = b >> 12 & 15, (b & 0xFFF) * (1 if a & 0x80 else -1)
            lit = ((pos + 4) & ~3) + delta
            values[reg] = unpack("<I", data, lit)[0] if 0 <= lit <= len(data) - 4 else None
            starts[reg] = pos
        elif a & 0xFBF0 == 0xF2C0 and not b & 0x8000:
            reg = b >> 8 & 15
            if values[reg] is not None:
                imm = (a & 15) << 12 | (a & 0x400) << 1 | (b & 0x7000) >> 4 | b & 255
                values[reg] = values[reg] & 0xFFFF | imm << 16
        elif a & 0xFF00 == 0x4400:
            reg, other = (a & 7) | (a & 0x80) >> 4, a >> 3 & 15
            if other == 15 and values[reg] is not None:
                values[reg] = (values[reg] + pos + 4) & 0xFFFFFFFF
                if values[reg] == target and starts[reg] is not None and pos - starts[reg] <= 16:
                    matches.append(starts[reg])
            else:
                values[reg] = None
        # Do not carry a guessed string value across calls or returns.
        elif (a & 0xF800 == 0xF000 and b & 0xD000 in (0xC000, 0xD000)) or a & 0xFF00 == 0xBD00:
            values, starts = [None] * 16, [None] * 16
        pos += width
    if len(set(matches)) != 1:
        raise ImageError("ASR message reference is missing or ambiguous")
    return matches[0]


def thumb_branch(source, target):
    delta = target - source - 4
    if source % 2 or target % 2 or not -(1 << 24) <= delta < (1 << 24):
        raise ImageError("Thumb branch is unaligned or out of range")
    s, i1, i2 = delta >> 24 & 1, delta >> 23 & 1, delta >> 22 & 1
    j1, j2 = 1 ^ i1 ^ s, 1 ^ i2 ^ s
    return struct.pack("<HH", 0xF000 | s << 10 | delta >> 12 & 0x3FF,
                       0x9000 | j1 << 13 | j2 << 11 | delta >> 1 & 0x7FF)


def patch_asr(original):
    text = code_range(original)
    check_or_update_hashes(original)
    passed = find_string_setup(original, text, b"Image passed signature verification")
    failed = find_string_setup(original, text, b"Image failed signature verification")
    if passed == failed or failed + 4 > text[1]:
        raise ImageError("Invalid ASR verification paths")
    result = bytearray(original)
    branch = thumb_branch(failed, passed)
    result[failed:failed + 4] = branch
    directories = check_or_update_hashes(result, update=True)
    check_or_update_hashes(result)
    return bytes(result), {"passed": passed, "failed": failed,
                           "before": original[failed:failed + 4].hex(),
                           "after": branch.hex(), "code_directories": len(directories)}


def relocate_dylibs(original, mapping):
    """Relocate temporary helpers without replacing stock system libraries.

    Only explicitly named dylib dependencies/IDs change, within their existing
    load commands. Socket's real bootstrap and package files remain untouched.
    """
    check_or_update_hashes(original)
    result = bytearray(original)
    changes = []
    for cmd, pos, size in commands(original):
        if cmd not in (0xC, 0xD, 0x80000018, 0x8000001F):
            continue
        name_offset = unpack("<I", original, pos + 8)[0]
        if name_offset < 24 or name_offset >= size:
            raise ImageError("Invalid dylib load command")
        raw = checked(original, pos + name_offset, size - name_offset)
        if b"\0" not in raw:
            raise ImageError("Unterminated dylib name")
        name = raw.split(b"\0", 1)[0].decode("utf-8")
        if name not in mapping:
            continue
        replacement = mapping[name].encode("utf-8") + b"\0"
        if len(replacement) > len(raw):
            raise ImageError("Relocated dylib name exceeds its existing load command")
        result[pos + name_offset:pos + size] = replacement.ljust(len(raw), b"\0")
        changes.append({"from": name, "to": mapping[name]})
    check_or_update_hashes(result, update=True)
    check_or_update_hashes(result)
    return bytes(result), changes
