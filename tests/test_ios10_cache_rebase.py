import ctypes
import shutil
import struct
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BASE = 0x350e9000
WORD = BASE + 0x40c


def cache(version=2):
    b = bytearray(0x4000)
    b[:16] = b'dyld_v1   armv7s\0'
    struct.pack_into('<II', b, 16, 0x100, 2)
    struct.pack_into('<QQQII', b, 0x100, 0x1a000000, 0x1000, 0, 5, 5)
    struct.pack_into('<QQQII', b, 0x120, BASE, 0x1000, 0x1000, 3, 3)
    struct.pack_into('<QQ', b, 56, 0x2000, 0x400)
    if version == 2:
        struct.pack_into('<6IQQ', b, 0x2000, 2, 4096, 40, 1, 42, 0,
                         0xe0000000, 0x1a000000)
        struct.pack_into('<H', b, 0x2028, 0x40c // 4)
    else:
        struct.pack_into('<6I', b, 0x2000, version, 24, 1, 26, 1, 128)
        bit = 0x40c // 4
        b[0x2000 + 26 + bit // 8] = 1 << (bit % 8)
    return b


class CacheRebaseTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cc = shutil.which('clang') or shutil.which('cc')
        if not cc:
            raise unittest.SkipTest('Host C compiler unavailable')
        cls.temp = tempfile.TemporaryDirectory()
        lib = Path(cls.temp.name) / 'rebase.so'
        subprocess.run([cc, '-std=c99', '-Wall', '-Wextra', '-Werror', '-shared',
                        '-fPIC', str(ROOT / 'resources/ios10/allinone/cache_rebase.c'),
                        '-o', str(lib)], check=True)
        cls.library = ctypes.CDLL(str(lib))
        cls.fn = cls.library.lik_cache_word
        cls.fn.argtypes = [ctypes.c_void_p, ctypes.c_size_t, ctypes.c_uint32,
                          ctypes.POINTER(ctypes.c_uint32), ctypes.POINTER(ctypes.c_int)]
        cls.fn.restype = ctypes.c_int

    @classmethod
    def tearDownClass(cls):
        cls.temp.cleanup()

    def read(self, b, address=WORD, size=None):
        buf = (ctypes.c_ubyte * len(b)).from_buffer(b)
        value, pointer = ctypes.c_uint32(), ctypes.c_int()
        result = self.fn(buf, len(b) if size is None else size, address,
                         ctypes.byref(value), ctypes.byref(pointer))
        return result, value.value, pointer.value

    def test_captured_crash_word_decodes_to_unslid_pointer(self):
        b = cache()
        struct.pack_into('<I', b, 0x140c, 0x5b0e9e98)
        self.assertEqual(self.read(b), (0, 0x350e9e98, 1))

    def test_other_captured_words_and_null_carrier(self):
        for raw, value, pointer in ((0x24cd4000, 0x1ecd4000, 1),
                (0x64cb8ad9, 0x1ecb8ad9, 1), (0x84ac89e1, 0x1eac89e1, 1),
                (0x40000000, 0, 0), (0, 0, 0)):
            with self.subTest(raw=hex(raw)):
                b = cache(); struct.pack_into('<I', b, 0x140c, raw)
                self.assertEqual(self.read(b), (0, value, pointer))

    def test_non_pointer_values_are_not_decoded_or_slid(self):
        for raw in (0x5b0e9e98, 0x350e9e98, 41, 0):
            b = cache(); struct.pack_into('<H', b, 0x2028, 0x4000)
            struct.pack_into('<I', b, 0x140c, raw)
            self.assertEqual(self.read(b), (0, raw, 0))

    def test_chain_membership_is_required_even_on_a_rebased_page(self):
        b = cache(); struct.pack_into('<I', b, 0x140c, 0x5b0e9e98)
        struct.pack_into('<I', b, 0x1400, 0x5b0e9e98)
        self.assertEqual(self.read(b, BASE + 0x400), (0, 0x5b0e9e98, 0))

    def test_follows_chains_and_multiple_starts(self):
        b = cache(); struct.pack_into('<H', b, 0x2028, 0x8000)
        struct.pack_into('<I', b, 0x2014, 2)
        struct.pack_into('<HH', b, 0x202a, 0x10 // 4, 0x8000 | (0x404 // 4))
        struct.pack_into('<I', b, 0x1404, 0x40000000)  # Null carrier, +8.
        struct.pack_into('<I', b, 0x140c, 0x5b0e9e98)
        self.assertEqual(self.read(b), (0, 0x350e9e98, 1))

    def test_v1_bitmap_marks_pointers_without_chained_encoding(self):
        b = cache(1); struct.pack_into('<I', b, 0x140c, 0x350e9e98)
        self.assertEqual(self.read(b), (0, 0x350e9e98, 1))
        struct.pack_into('<I', b, 0x1408, 0x350e9e98)
        self.assertEqual(self.read(b, BASE + 0x408), (0, 0x350e9e98, 0))
        struct.pack_into('<I', b, 0x140c, 0)
        self.assertEqual(self.read(b), (0, 0, 0))

    def test_rejects_unsupported_or_malformed_metadata(self):
        cases = []
        b = cache(); struct.pack_into('<I', b, 0x2000, 3); cases.append(b)
        b = cache(); struct.pack_into('<Q', b, 0x2018, 0xa0000000); cases.append(b)
        b = cache(); struct.pack_into('<Q', b, 0x2020, 0xffffffff)
        struct.pack_into('<I', b, 0x140c, 1); cases.append(b)
        b = cache(); struct.pack_into('<H', b, 0x2028, 0x8000); cases.append(b)
        b = cache(); struct.pack_into('<H', b, 0x2028, 0x3fff); cases.append(b)
        b = cache(); struct.pack_into('<I', b, 0x2008, 0x3ff); cases.append(b)
        b = cache(); struct.pack_into('<H', b, 0x2028, 0xffc // 4)
        struct.pack_into('<I', b, 0x1ffc, 0xe0000000); cases.append(b)
        b = cache(1); struct.pack_into('<H', b, 0x2018, 5); cases.append(b)
        for i, b in enumerate(cases):
            with self.subTest(case=i): self.assertEqual(self.read(b)[0], -1)

    def test_bounds_and_alignment(self):
        for size in (0, 87, 0x101, 0x2002):
            self.assertEqual(self.read(cache(), size=size)[0], -1)
        for address in (WORD + 1, 0, BASE + 4096):
            self.assertEqual(self.read(cache(), address)[0], -1)


if __name__ == '__main__':
    unittest.main()
