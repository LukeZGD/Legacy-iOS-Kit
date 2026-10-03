# SPDX-License-Identifier: GPL-3.0-or-later
"""Read prelinked driver metadata from a 32-bit iOS kernel cache."""
import argparse
import json
import struct
import xml.etree.ElementTree as ET
from pathlib import Path


def segments(blob):
    if blob[:4] != bytes.fromhex('cefaedfe'):
        raise ValueError('expected a decompressed, little-endian Mach-O32')
    offset = 28
    for _ in range(struct.unpack_from('<I', blob, 16)[0]):
        command, size = struct.unpack_from('<II', blob, offset)
        if command == 1:
            values = struct.unpack_from('<II16sIIIIIIII', blob, offset)
            yield dict(name=values[2].rstrip(b'\0').decode(),
                       address=values[3], vmsize=values[4],
                       offset=values[5], size=values[6])
        offset += size


def metadata(blob):
    info = next(s for s in segments(blob) if s['name'] == '__PRELINK_INFO')
    root = ET.fromstring(blob[info['offset']:info['offset'] + info['size']].rstrip(b'\0'))
    ids = {e.attrib['ID']: e for e in root.iter() if 'ID' in e.attrib}

    def decode(e):
        if 'IDREF' in e.attrib:
            return decode(ids[e.attrib['IDREF']])
        if e.tag == 'plist':
            return decode(e[0])
        if e.tag == 'dict':
            children = list(e)
            return {children[i].text: decode(children[i + 1])
                    for i in range(0, len(children), 2)}
        if e.tag == 'array':
            return [decode(child) for child in e]
        if e.tag == 'integer':
            return int(e.text, 0)
        if e.tag in ('true', 'false'):
            return e.tag == 'true'
        return e.text or ''

    return decode(root)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('kernel', type=Path)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    result = metadata(args.kernel.read_bytes())
    if args.output:
        args.output.write_text(json.dumps(result, indent=2))
    for driver in result['_PrelinkInfoDictionary']:
        name = driver['CFBundleIdentifier']
        if any(word in name.lower() for word in ('audio', 'gyro', 'accelerometer')):
            print(name, json.dumps(driver.get('IOKitPersonalities', {})))
