#!/usr/bin/env python3
"""Rebuild our p0insettia-derived jump-start payload; no device access.

Use --prefix /path/to/arm-none-eabi- (GCC/binutils). The compiler is a build
dependency, not a runtime dependency of Legacy iOS Kit. Upstream source and its
licenses are in payload-src. Unlike upstream mk.sh this does not bump versions,
remove source files, or produce a payload that replaces Apple's launchd.
"""

import argparse
import hashlib
import json
from pathlib import Path
import struct
import subprocess


def assemble(hook, prehook):
    position = prehook.find(hook)
    if position < 0 or prehook.find(hook, position + 1) >= 0:
        raise ValueError("Expected exactly one complete embedded kernel hook")
    trampoline = struct.pack("<I", 0xDEADBEEF)
    flag = struct.pack("<I", 0xDEADFEED)
    if prehook.count(trampoline) != 1 or prehook.count(flag) != 1:
        raise ValueError("Payload trampoline/launchd-mode marker is ambiguous")
    result = prehook.replace(trampoline, struct.pack("<I", 0x80000000 + position))
    # Keeping the nonzero flag suppresses /sbin/launchd -> /haxx/launchd.
    assert result.count(flag) == 1
    return result, position


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--prefix", required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    source = Path(__file__).resolve().parent / "payload-src"
    version = subprocess.check_output([args.prefix + "gcc", "--version"], text=True).splitlines()[0]
    for part in ("hook", "prehook"):
        if part == "prehook":
            hook = (source / "hook/payload").read_bytes()
            header = "unsigned char payload[] = {\n" + ",\n".join(
                ",".join(f"0x{b:02x}" for b in hook[i:i + 16]) for i in range(0, len(hook), 16))
            header += "\n};\nunsigned int payload_len = " + str(len(hook)) + ";\n"
            (source / "prehook/payload.h").write_text(header)
        subprocess.run(["make", "GNUARM_PREFIX=" + args.prefix], cwd=source / part, check=True)
    payload, offset = assemble(hook, (source / "prehook/payload").read_bytes())
    args.output.write_bytes(payload)
    source_hashes = {}
    for file in sorted(source.rglob("*")):
        if file.is_file() and (file.suffix in (".c", ".h", ".S", ".ld") or file.name == "Makefile"):
            if file.name == "payload.h":
                continue
            source_hashes[str(file.relative_to(source))] = hashlib.sha256(file.read_bytes()).hexdigest()
    audit = {"compiler": version, "sha256": hashlib.sha256(payload).hexdigest(),
             "size": len(payload), "hook_offset": offset, "stock_launchd": True,
             "hardware_tested": False, "source_sha256": source_hashes}
    args.output.with_suffix(".build.json").write_text(json.dumps(audit, indent=2) + "\n")
    print("Built experimental jump-start payload; hardware testing remains required.")


if __name__ == "__main__":
    main()
