"""Offline image checks; synthetic executables contain no Apple firmware.

The firmware integration build is separate and does not access any USB device.
"""

import copy
import hashlib
import io
import json
from pathlib import Path
import struct
import sys
import tarfile
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "resources/ios10"))
from macho import ImageError, check_or_update_hashes, patch_asr, thumb_branch
from prepare import select_identity, validate_stage, validate_runtime, rewrite_zip, Runner


def synthetic_asr(algorithm=1):
    """Tiny ARM Mach-O with genuine page hashes and two string references."""
    data = bytearray(0x2000)
    struct.pack_into("<7I", data, 0, 0xFEEDFACE, 12, 9, 2, 2, 140, 0)
    struct.pack_into("<II16s8I", data, 28, 1, 124, b"__TEXT", 0x4000,
                     0x2000, 0, 0x2000, 5, 5, 1, 0)
    struct.pack_into("<16s16s9I", data, 84, b"__text", b"__TEXT", 0x5000,
                     32, 0x1000, 1, 0, 0, 0x80000400, 0, 0)
    for off in range(0x1000, 0x1020, 2):
        struct.pack_into("<H", data, off, 0xBF00)
    for start, target, string in ((0x1000, 0x1200, b"Image passed signature verification\0"),
                                   (0x1010, 0x1300, b"Image failed signature verification\0")):
        # movw r0, #(target-PC); movt r0, #0; add r0, pc
        imm = target - (start + 8 + 4)
        struct.pack_into("<5H", data, start, 0xF240 | (imm >> 12) | ((imm >> 11 & 1) << 10),
                         (imm >> 8 & 7) << 12 | imm & 255, 0xF2C0, 0, 0x4478)
        data[target:target + len(string)] = string
    hash_len = 20 if algorithm == 1 else 32
    cd = bytearray(48 + 2 * hash_len)
    struct.pack_into(">9I4BI", cd, 0, 0xFADE0C02, len(cd), 0x20000, 2,
                     48, 44, 0, 2, len(data), hash_len, algorithm, 0, 12, 0)
    cd[44:48] = b"asr\0"
    sig = struct.pack(">5I", 0xFADE0CC0, 20 + len(cd), 1, 0, 20) + cd
    struct.pack_into("<4I", data, 152, 0x1D, 16, len(data), len(sig))
    data.extend(sig)
    check_or_update_hashes(data, update=True)
    return bytes(data)


class ASRTests(unittest.TestCase):
    def test_redirects_failure_and_repairs_each_supported_hash_type(self):
        for algorithm in (1, 2):
            with self.subTest(algorithm=algorithm):
                original = synthetic_asr(algorithm)
                patched, report = patch_asr(original)
                self.assertEqual((report["passed"], report["failed"]), (0x1000, 0x1010))
                self.assertEqual(patched[0x1010:0x1014], bytes.fromhex("fff7f6bf"))
                check_or_update_hashes(patched)
                self.assertEqual(original[:0x1010], patched[:0x1010])
                self.assertEqual(original[0x1014:0x2000], patched[0x1014:0x2000])

    def test_corrupt_original_is_rejected_before_patching(self):
        data = bytearray(synthetic_asr())
        data[0x1800] ^= 1
        with self.assertRaisesRegex(ImageError, "code hash"):
            patch_asr(bytes(data))

    def test_missing_or_ambiguous_reference_fails(self):
        for replacement in (b"Xmage passed", b"Image failed"):
            data = bytearray(synthetic_asr())
            data[0x1200:0x1200 + len(replacement)] = replacement
            check_or_update_hashes(data, update=True)
            with self.assertRaises(ImageError):
                patch_asr(bytes(data))

    def test_truncated_macho_and_signature_are_rejected(self):
        original = synthetic_asr()
        for end in (0, 20, 100, 0x2000, len(original) - 1):
            with self.subTest(end=end), self.assertRaises(ImageError):
                patch_asr(original[:end])

    def test_invalid_command_length_is_rejected(self):
        data = bytearray(synthetic_asr())
        struct.pack_into("<I", data, 32, 0)
        with self.assertRaises(ImageError):
            patch_asr(data)

    def test_branch_alignment_and_range(self):
        for source, target in ((1, 4), (0, 3), (0, 0x1000004)):
            with self.assertRaises(ImageError):
                thumb_branch(source, target)


class PreparationTests(unittest.TestCase):
    def test_apple_14g61_manifest_covers_all_four_iphone_models(self):
        # Extracted facts from Apple's actual IPSW, including both 5c boards.
        manifest = json.loads((ROOT / "tests/fixtures/iphone-14G61-identities.json").read_text())
        for product, board in (("iPhone5,1", "n41ap"), ("iPhone5,2", "n42ap"),
                               ("iPhone5,3", "n48ap"), ("iPhone5,4", "n49ap")):
            with self.subTest(product=product):
                selected = select_identity(manifest, product, board, "10.3.4", "14G61")
                self.assertEqual(selected["Info"]["RestoreBehavior"], "Erase")
                self.assertEqual(selected["Manifest"]["OS"]["Info"]["Path"], "058-74968-065.dmg")
                self.assertEqual(selected["Manifest"]["DeviceTree"]["Info"]["Path"],
                                 "Firmware/all_flash/DeviceTree." + board + ".img3")

    def identity_manifest(self):
        manifest = {key: {"Info": {"Path": key + ".bin"}} for key in
                    ("OS", "iBSS", "iBEC", "RestoreRamDisk", "KernelCache", "iBoot")}
        return {"ProductVersion": "10.3.3", "ProductBuildVersion": "14G60",
                "SupportedProductTypes": ["iPhone5,1", "iPhone5,3"],
                "BuildIdentities": [{"Info": {"DeviceClass": "n41ap", "RestoreBehavior": "Erase"}, "Manifest": manifest},
                                    {"Info": {"DeviceClass": "n48ap", "RestoreBehavior": "Update"}, "Manifest": manifest},
                                    {"Info": {"DeviceClass": "n48ap", "RestoreBehavior": "Erase"}, "Manifest": manifest}]}

    def test_selects_target_erase_identity_instead_of_first_identity(self):
        m = self.identity_manifest()
        self.assertIs(select_identity(m, "iPhone5,3", "n48ap", "10.3.3", "14G60"), m["BuildIdentities"][2])

    def test_wrong_device_build_or_duplicate_identity_rejected(self):
        m = self.identity_manifest()
        for args in (("iPhone5,3", "n41ap", "10.3.3", "14G60"),
                     ("iPhone5,3", "n48ap", "10.3.4", "14G61"),
                     ("iPad3,4", "p101ap", "10.3.3", "14G60")):
            with self.assertRaises(ImageError):
                select_identity(m, *args)
        m["BuildIdentities"].append(copy.deepcopy(m["BuildIdentities"][2]))
        with self.assertRaises(ImageError):
            select_identity(m, "iPhone5,3", "n48ap", "10.3.3", "14G60")

    def archive(self, path, name, kind=tarfile.REGTYPE, include_parent=True):
        with tarfile.open(path, "w") as t:
            if include_parent:
                d = tarfile.TarInfo("usr/local/share/lik-ios10/")
                d.mode, d.type = 0o755, tarfile.DIRTYPE
                t.addfile(d)
            m = tarfile.TarInfo(name)
            m.mode, m.type = 0o644, kind
            if kind == tarfile.REGTYPE:
                m.size = 7
                t.addfile(m, io.BytesIO(b"payload"))
            else:
                m.linkname = "/private/var"
                t.addfile(m)

    def test_internal_runtime_allows_payloads_but_not_live_trigger_or_data_paths(self):
        with tempfile.TemporaryDirectory() as tmp:
            archive = Path(tmp) / "stage.tar"
            path = "usr/local/share/lik-ios10/procyon.deb"
            self.archive(archive, path)
            self.assertEqual(validate_runtime(archive)[path], hashlib.sha256(b"payload").hexdigest())
            for name in ("private/var/root/procyon/stage3.bin", "usr/libexec/wifiFirmwareLoaderLegacy",
                         "../payload", "/payload"):
                self.archive(archive, name)
                with self.assertRaises(ImageError):
                    validate_runtime(archive)
            self.archive(archive, path, tarfile.SYMTYPE)
            with self.assertRaises(ImageError):
                validate_runtime(archive)
            self.archive(archive, path, include_parent=False)
            with self.assertRaises(ImageError):
                validate_runtime(archive)

    def test_zip_changes_only_selected_components_and_preserves_source(self):
        with tempfile.TemporaryDirectory() as tmp:
            p = Path(tmp)
            source, output, replacement = p / "stock.zip", p / "custom.zip", p / "replacement"
            with zipfile.ZipFile(source, "w", compression=zipfile.ZIP_DEFLATED) as z:
                z.writestr("root.dmg", b"original")
                z.writestr("kernelcache", b"unchanged kernel")
            before = source.read_bytes()
            replacement.write_bytes(b"new filesystem" * 100)
            rewrite_zip(source, output, {"root.dmg": replacement})
            self.assertEqual(source.read_bytes(), before)
            with zipfile.ZipFile(output) as z:
                self.assertEqual(z.read("root.dmg"), replacement.read_bytes())
                self.assertEqual(z.read("kernelcache"), b"unchanged kernel")
            with self.assertRaises(ImageError):
                rewrite_zip(source, output, {})

    def test_bundled_assets_match_pinned_digests(self):
        assets = ROOT / "resources/ios10/assets"
        for name, expected in json.loads((assets / "manifest.json").read_text())["sha256"].items():
            with self.subTest(asset=name):
                self.assertEqual(hashlib.sha256((assets / name).read_bytes()).hexdigest(), expected)


if __name__ == "__main__":
    unittest.main()
