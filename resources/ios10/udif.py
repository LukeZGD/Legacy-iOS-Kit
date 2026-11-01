"""Make xpwn's HFS DMG deterministic when restored onto existing storage.

xpwn's dmg build emits IGNORE runs for long runs of zero bytes, including
bytes inside allocated files. Disk-image readers return zeros for these runs,
but ASR may leave existing destination bytes there. Emit ordinary compressed
zero payloads for every such run in the HFS partition. Preserve other partition
semantics and rebuild the ASR checksums and sequential payload offsets.
"""
import hashlib
from pathlib import Path
import plistlib
import struct
import zlib

from macho import ImageError

RAW, IGNORE, ZLIB = 1, 2, 0x80000005
COMMENT, END = 0x7ffffffe, 0xffffffff
CHUNK = 256 * 1024


def require(ok, message):
    if not ok:
        raise ImageError("Restore image: " + message)


def exact(stream, count):
    data = stream.read(count)
    require(len(data) == count, "truncated data")
    return data


def metadata(stream):
    stream.seek(0, 2)
    length = stream.tell()
    require(length >= 512, "missing UDIF trailer")
    stream.seek(-512, 2)
    trailer = bytearray(exact(stream, 512))
    require(trailer[:4] == b"koly" and struct.unpack_from(">II", trailer, 4) == (4, 512), "unsupported UDIF header")
    data_offset, data_size, rsrc_offset, rsrc_size = struct.unpack_from(">4Q", trailer, 24)
    require(data_offset == rsrc_offset == rsrc_size == 0, "unexpected data/resource fork layout")
    require(struct.unpack_from(">II", trailer, 56) == (1, 1), "segmented images are unsupported")
    offset, size = struct.unpack_from(">QQ", trailer, 216)
    require(offset == data_size and 0 < size <= 16 * 1024**2 and offset + size == length - 512, "invalid XML bounds")
    stream.seek(offset)
    try:
        resources = plistlib.loads(exact(stream, size))["resource-fork"]
    except (ValueError, KeyError, TypeError) as exc:
        raise ImageError("Restore image: invalid resources") from exc
    return trailer, resources, data_size


def materialize_hfs_zeros(source, output, raw_hfs, progress=None):
    """Write a new DMG; never replace the source on failure. Stdlib only."""
    source, output, raw_hfs = map(Path, (source, output, raw_hfs))
    require(source.resolve() != output.resolve(), "source and output must differ")
    require(not output.exists(), "output already exists")
    with source.open("rb") as inp, raw_hfs.open("rb") as raw:
        trailer, resources, data_size = metadata(inp)
        tables = resources.get("blkx", [])
        hfs = [e for e in tables if "Apple_HFS" in e.get("Name", "")]
        require(len(hfs) == 1, "expected one HFS partition")
        hfs_id = hfs[0]["ID"]
        crc = 0
        hfs_crc = 0
        hfs_sha = hashlib.sha1()
        expanded_runs = expanded_bytes = 0
        consumed = 0
        try:
            with output.open("xb") as out:
                for entry in tables:
                    data = entry["Data"]
                    require(len(data) >= 204 and data[:4] == b"mish", "invalid BLKX header")
                    count = struct.unpack_from(">I", data, 200)[0]
                    require(len(data) == 204 + count * 40, "invalid BLKX run count")
                    header = bytearray(data[:204])
                    base = struct.unpack_from(">Q", data, 24)[0]
                    sectors = struct.unpack_from(">Q", data, 16)[0]
                    is_hfs = entry is hfs[0]
                    if is_hfs:
                        require(sectors * 512 == raw_hfs.stat().st_size, "HFS size mismatch")
                    runs = []
                    cursor = 0

                    def emit(kind, reserved, start, nsectors, payload):
                        nonlocal crc
                        runs.append(struct.pack(">II4Q", kind, reserved, start, nsectors, out.tell(), len(payload)))
                        out.write(payload)
                        crc = zlib.crc32(payload, crc)

                    def check_hfs(decoded):
                        nonlocal hfs_crc, consumed
                        require(exact(raw, len(decoded)) == decoded, "encoded HFS does not match the prepared filesystem")
                        hfs_crc = zlib.crc32(decoded, hfs_crc)
                        hfs_sha.update(decoded)
                        consumed += len(decoded)
                        if progress is not None:
                            progress.update(consumed)

                    for i in range(count):
                        kind, reserved, start, nsectors, offset, size = struct.unpack_from(">II4Q", data, 204 + i * 40)
                        require(kind in (RAW, IGNORE, ZLIB, COMMENT, END), "unsupported block encoding")
                        if kind in (COMMENT, END):
                            require(nsectors == size == 0, "invalid non-data run")
                            if kind == END:
                                require(i == count - 1 and cursor == sectors, "incomplete partition")
                            emit(kind, reserved, start, 0, b"")
                            continue
                        require(nsectors > 0 and start == cursor and start + nsectors <= sectors, "overlapping or missing sectors")
                        cursor += nsectors
                        if kind == IGNORE:
                            require(size == 0, "IGNORE run contains a payload")
                            if not is_hfs:
                                emit(kind, reserved, start, nsectors, b"")
                                continue
                            expanded_runs += 1
                            expanded_bytes += nsectors * 512
                            while nsectors:
                                n = min(nsectors, CHUNK // 512)
                                zeros = bytes(n * 512)
                                check_hfs(zeros)
                                emit(ZLIB, 0, start, n, zlib.compress(zeros, 1))
                                start += n
                                nsectors -= n
                            continue
                        require(0 < size <= 2 * 1024**2 and nsectors * 512 <= 2 * 1024**2 and base + offset + size <= data_size, "invalid payload bounds")
                        inp.seek(base + offset)
                        payload = exact(inp, size)
                        if is_hfs:
                            if kind == ZLIB:
                                decoder = zlib.decompressobj()
                                decoded = decoder.decompress(payload, nsectors * 512 + 1)
                                require(decoder.eof and not decoder.unused_data and not decoder.unconsumed_tail, "invalid compressed payload")
                            else:
                                decoded = payload
                            require(len(decoded) == nsectors * 512, "decoded sector count mismatch")
                            check_hfs(decoded)
                        emit(kind, reserved, start, nsectors, payload)
                    require(count > 0 and struct.unpack_from(">I", runs[-1])[0] == END, "missing partition terminator")
                    struct.pack_into(">Q", header, 24, 0)
                    struct.pack_into(">I", header, 32, max(struct.unpack_from(">I", header, 32)[0], CHUNK // 512))
                    struct.pack_into(">I", header, 200, len(runs))
                    if is_hfs:
                        require(struct.unpack_from(">II", header, 64) == (2, 32), "unsupported HFS checksum")
                        struct.pack_into(">I", header, 72, hfs_crc)
                    entry["Data"] = bytes(header) + b"".join(runs)
                require(consumed == raw_hfs.stat().st_size and raw.read(1) == b"", "incomplete HFS verification")
                nsiz = [e for e in resources.get("nsiz", []) if e.get("ID") == hfs_id]
                require(len(nsiz) == 1, "missing HFS ASR checksum")
                values = plistlib.loads(nsiz[0]["Data"])
                require("SHA-1-digest" in values, "missing ASR SHA1 field")
                values["SHA-1-digest"] = hfs_sha.digest()
                # Each added zero span is a multiple of 512 bytes: the MediaKit
                # rotate/add checksum rotates a multiple of 32 bits, unchanged.
                nsiz[0]["Data"] = plistlib.dumps(values, sort_keys=False)
                xml = plistlib.dumps({"resource-fork": resources}, sort_keys=False)
                fork_size = out.tell()
                struct.pack_into(">Q", trailer, 32, fork_size)
                struct.pack_into(">II", trailer, 80, 2, 32)
                trailer[88:216] = bytes(128)
                struct.pack_into(">I", trailer, 88, crc)
                struct.pack_into(">QQ", trailer, 216, fork_size, len(xml))
                master = b"".join(e["Data"][72:76] for e in tables if struct.unpack_from(">I", e["Data"], 64)[0] == 2)
                struct.pack_into(">II", trailer, 352, 2, 32)
                trailer[360:488] = bytes(128)
                struct.pack_into(">I", trailer, 360, zlib.crc32(master))
                out.write(xml)
                out.write(trailer)
            return {"ignore_runs_materialized": expanded_runs, "zero_bytes_written": expanded_bytes,
                    "hfs_sha1": hfs_sha.hexdigest(), "hfs_crc32": "%08x" % hfs_crc,
                    "hfs_ignore_runs_remaining": 0}
        except Exception:
            if output.exists():
                output.unlink()
            raise
