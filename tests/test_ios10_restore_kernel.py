"""Bounded patch and manifest-routing tests with synthetic ARM Mach-O data."""
import copy
from pathlib import Path
import plistlib
import struct
import sys
import tempfile
import unittest
from unittest.mock import patch
import zipfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'resources/ios10'))
from macho import ImageError
from restore_kernel import IDENTIFIER, MESSAGE, patch_restore_kernel
from prepare import prepare_restore_components, RESTORE_KERNEL_PATH, rewrite_zip


def synthetic_kernel():
    kernel = bytearray(0x4000)
    struct.pack_into('<7I', kernel, 0, 0xFEEDFACE, 12, 9, 2, 1, 56, 0)
    struct.pack_into('<II16s8I', kernel, 28, 1, 56, b'__PRELINK_TEXT',
                     0x80001000, 0x3000, 0x1000, 0x3000, 5, 5, 0, 0)
    amfi = bytearray(0x3000)
    struct.pack_into('<7I', amfi, 0, 0xFEEDFACE, 12, 9, 2, 2, 180, 0)
    struct.pack_into('<II16s8I', amfi, 28, 1, 124, b'__TEXT',
                     0x80001000, 0x2000, 0, 0x2000, 5, 5, 1, 0)
    struct.pack_into('<16s16s9I', amfi, 84, b'__text', b'__TEXT',
                     0x80001ff0, 0x210, 0xff0, 1, 0, 0, 0x80000400, 0, 0)
    struct.pack_into('<II16s8I', amfi, 152, 1, 56, b'__DATA',
                     0x80003000, 0x1000, 0x2000, 0x1000, 3, 3, 0, 0)
    amfi[0xff0:0x1200] = b'\x00\xbf' * 264
    struct.pack_into('<H',amfi,0xff0,0xb5f0)
    amfi[0x1000:0x1014] = bytes.fromhex('584600f041fd06468eb13046fdf75afd012815d1')
    start, target = 0x1022, 0x1300
    imm = target - (start + 8 + 4)
    struct.pack_into('<5H', amfi, start, 0xF240 | (imm >> 12) | ((imm >> 11 & 1) << 10),
                     (imm >> 8 & 7) << 12 | imm & 255, 0xF2C0, 0, 0x4478)
    amfi[target:target + len(MESSAGE) + 1] = MESSAGE + b'\0'
    amfi[0x2100:0x2100 + len(IDENTIFIER)] = IDENTIFIER
    kernel[0x1000:] = amfi
    return bytes(kernel)


class RestoreKernelTests(unittest.TestCase):
    def test_changes_only_identified_twenty_byte_check(self):
        original = synthetic_kernel()
        result, audit = patch_restore_kernel(original)
        self.assertEqual(len(result), len(original))
        self.assertEqual(audit['file_offset'], 0x2000)
        self.assertEqual(audit['virtual_address'], 0x80002000)
        self.assertEqual(result[:0x2000], original[:0x2000])
        self.assertEqual(result[0x2014:], original[0x2014:])
        self.assertEqual(result[0x2000:0x2014], b'\x00\xbf' * 10)
        with self.assertRaises(ImageError):
            patch_restore_kernel(result)

    def test_missing_ambiguous_and_out_of_bounds_data_are_rejected(self):
        original = synthetic_kernel()
        broken = []
        data = bytearray(original)
        data[0x2000:0x2014] = b'\x00' * 20
        broken.append(data)
        data = bytearray(original)
        data[0x2100:0x2114] = data[0x2000:0x2014]
        struct.pack_into('<H', data, 0x2012, 0xd000)
        broken.append(data)
        data = bytearray(original)
        data[0x2300] = ord('X')
        broken.append(data)
        data = bytearray(original)
        data[0x3200:0x3200 + len(IDENTIFIER)] = IDENTIFIER
        broken.append(data)
        broken += [original[:n] for n in (0, 20, 80, 0x2000, 0x3100)]
        for data in broken:
            with self.subTest(size=len(data)), self.assertRaises(ImageError):
                patch_restore_kernel(data)

    def test_manifest_routes_only_selected_restore_kernel_and_preserves_digests(self):
        component = {'Info': {'Path': 'kernelcache'}, 'Digest': b'Apple ticket digest'}
        identity = {'Info': {'DeviceClass': 'n49ap', 'RestoreBehavior': 'Erase'},
                    'Manifest': {'KernelCache': copy.deepcopy(component), 'RestoreKernelCache': copy.deepcopy(component)}}
        manifest = {'BuildIdentities': [copy.deepcopy(identity), identity]}
        manifest['BuildIdentities'][0]['Info']['DeviceClass'] = 'n48ap'
        before = copy.deepcopy(manifest)
        with tempfile.TemporaryDirectory() as tmp:
            work = Path(tmp)
            def fake_kernel(runner, source, output):
                output.write_bytes(b'temporary patched kernel')
                return {'hardware_tested': False}
            with patch('prepare.prepare_restore_kernel', side_effect=fake_kernel):
                replacements, audit = prepare_restore_components(None, work / 'stock', work, manifest, identity)
            changed = plistlib.loads(replacements['BuildManifest.plist'].read_bytes())
            self.assertEqual(manifest, before)
            self.assertEqual(changed['BuildIdentities'][0], before['BuildIdentities'][0])
            entries = changed['BuildIdentities'][1]['Manifest']
            self.assertEqual(entries['KernelCache'], component)
            self.assertEqual(entries['RestoreKernelCache']['Info']['Path'], RESTORE_KERNEL_PATH)
            self.assertEqual(entries['RestoreKernelCache']['Digest'], component['Digest'])
            stock, output = work / 'stock.zip', work / 'custom.zip'
            with zipfile.ZipFile(stock, 'w') as archive:
                archive.writestr('kernelcache', b'stock installed kernel')
                archive.writestr('BuildManifest.plist', plistlib.dumps(manifest))
            rewrite_zip(stock, output, replacements)
            with zipfile.ZipFile(output) as archive:
                self.assertEqual(archive.read('kernelcache'), b'stock installed kernel')
                self.assertEqual(archive.read(RESTORE_KERNEL_PATH), b'temporary patched kernel')
