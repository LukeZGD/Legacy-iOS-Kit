"""ASR-style writes to dirty storage must restore allocated zero-filled bytes."""
import hashlib
from pathlib import Path
import plistlib
import struct
import sys
import tempfile
import unittest
import zlib
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'resources/ios10'))
from udif import materialize_hfs_zeros, metadata, ImageError


def fixture(directory):
    # The zero span starts inside a 4 KiB page, as in the hardware failure.
    first, zero, last = b'A' * 2560, bytes(1536), b'B' * 2048
    raw = first + zero + last
    header = bytearray(204)
    header[:4] = b'mish'
    struct.pack_into('>I', header, 4, 1)
    struct.pack_into('>Q', header, 16, 12)
    struct.pack_into('>I', header, 32, 520)
    struct.pack_into('>II', header, 64, 2, 32)
    struct.pack_into('>I', header, 72, zlib.crc32(first + last))
    struct.pack_into('>I', header, 200, 4)
    runs = b''.join(struct.pack('>II4Q', *r) for r in [(1,0,0,5,0,len(first)), (2,0,5,3,len(first),0), (1,0,8,4,len(first),len(last)), (0xffffffff,0,12,0,len(first+last),0)])
    resources = {'blkx':[{'ID':'2','Name':'Test (Apple_HFSX : 3)','Data':bytes(header)+runs}], 'nsiz':[{'ID':'2','Data':plistlib.dumps({'SHA-1-digest':hashlib.sha1(first+last).digest(),'block-checksum-2':123})}]}
    xml=plistlib.dumps({'resource-fork':resources});tr=bytearray(512);tr[:4]=b'koly';struct.pack_into('>II',tr,4,4,512);struct.pack_into('>Q',tr,32,len(first+last));struct.pack_into('>II',tr,56,1,1);struct.pack_into('>QQ',tr,216,len(first+last),len(xml))
    source=directory/'source.dmg';source.write_bytes(first+last+xml+tr)
    raw_path=directory/'raw.hfs';raw_path.write_bytes(raw)
    return source,raw_path,raw


def asr_write(image):
    with image.open('rb') as f:
        trailer,resources,forksize=metadata(f);table=resources['blkx'][0]['Data'];result=bytearray(b'\xcc'*(struct.unpack_from('>Q',table,16)[0]*512))
        for off in range(204,len(table),40):
            kind,_,start,n,co,cl=struct.unpack_from('>II4Q',table,off)
            if kind not in (1,0x80000005):continue
            f.seek(co);payload=f.read(cl);decoded=zlib.decompress(payload) if kind==0x80000005 else payload
            assert len(decoded)==n*512
            result[start*512:(start+n)*512]=decoded
        return bytes(result),trailer,resources,forksize


class UDIFTests(unittest.TestCase):
    def test_dirty_destination_zero_bytes_and_checksums(self):
        with tempfile.TemporaryDirectory() as d:
            d=Path(d);source,raw,expected=fixture(d);out=d/'out.dmg'
            self.assertNotEqual(asr_write(source)[0],expected)
            audit=materialize_hfs_zeros(source,out,raw)
            actual,tr,res,size=asr_write(out)
            self.assertEqual(actual,expected)
            self.assertEqual(audit['zero_bytes_written'],1536)
            self.assertEqual(audit['hfs_ignore_runs_remaining'],0)
            self.assertEqual(struct.unpack_from('>I',res['blkx'][0]['Data'],72)[0],zlib.crc32(expected))
            self.assertEqual(plistlib.loads(res['nsiz'][0]['Data'])['SHA-1-digest'],hashlib.sha1(expected).digest())
            self.assertEqual(struct.unpack_from('>I',tr,88)[0],zlib.crc32(out.read_bytes()[:size]))
            self.assertEqual(struct.unpack_from('>I',tr,360)[0],zlib.crc32(res['blkx'][0]['Data'][72:76]))
            self.assertEqual(plistlib.loads(res['nsiz'][0]['Data'])['block-checksum-2'],123)

    def test_rejects_nonzero_bytes_hidden_by_ignore_run(self):
        with tempfile.TemporaryDirectory() as d:
            d=Path(d);src,raw,data=fixture(d);raw.write_bytes(data[:2560]+b'x'+data[2561:]);out=d/'out'
            with self.assertRaisesRegex(ImageError,'does not match'):materialize_hfs_zeros(src,out,raw)
            self.assertFalse(out.exists())

    def test_rejects_truncated_payload_and_preserves_source(self):
        with tempfile.TemporaryDirectory() as d:
            d=Path(d);src,raw,_=fixture(d);original=src.read_bytes();src.write_bytes(original[:-12]);out=d/'out'
            with self.assertRaises(ImageError):materialize_hfs_zeros(src,out,raw)
            self.assertEqual(src.read_bytes(),original[:-12]);self.assertFalse(out.exists())

    def test_refuses_to_overwrite_existing_output(self):
        with tempfile.TemporaryDirectory() as d:
            d=Path(d);src,raw,_=fixture(d);out=d/'out';out.write_bytes(b'keep')
            with self.assertRaisesRegex(ImageError,'already exists'):materialize_hfs_zeros(src,out,raw)
            self.assertEqual(out.read_bytes(),b'keep')

if __name__=='__main__':unittest.main()
