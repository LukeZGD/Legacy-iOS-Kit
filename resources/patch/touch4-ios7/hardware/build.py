# SPDX-License-Identifier: GPL-3.0-or-later
"""Build offline N81 kernel and rootfs patches; never access a device."""
import argparse
import hashlib
import io
import json
import plistlib
from pathlib import Path
import struct
import subprocess
import sys
import tarfile
import tempfile
from macho import MachO

HERE = Path(__file__).resolve().parent
PRODUCT = 'f5ec81b7cc2f189c169b47dc78eb4acf1f940103'
FIRMWARE = 'BCM4329B1_002.002.023.1019.1021_LOCO_052512.hcd'


def require_hash(blob, expected, label):
    actual = hashlib.sha256(blob).hexdigest()
    if actual != expected:
        raise ValueError(f'Unsupported {label}: SHA256 {actual}; expected {expected}')


def patch_btserver(blob):
    require_hash(blob, '2adcc0b16dc5f976c6ba80907bd6e1dba1ec395fbcc40c905dc4a543e4053c6e', '11D257 BTServer')
    result = bytearray(blob)
    offset = 0x15b63c
    old = b'832639820b5d5d92a684bdc15a9725c3e29cc13c'
    if result[offset:offset + len(old)] != old:
        raise ValueError('BTServer product classifier guard failed')
    result[offset:offset + len(old)] = PRODUCT.encode()
    offset = 0x163654
    if struct.unpack_from('<I', result, offset)[0] != 0x76f1d:
        raise ValueError('BTServer isSupported guard failed')
    struct.pack_into('<I', result, offset, 0x94f81)
    require_hash(result, '51e03672e4ec855c4182fb29f92e32f0233c75217de6e9779fdd7e2788a9c23e', 'unsigned patched BTServer')
    return bytes(result)


def bluetooth_resources(bluetool):
    require_hash(bluetool, '7a422e18b4625d8944c7800dfede97f888ef15536f5c4b096d3ddfb57cf743c9', '10B500 BlueTool')
    # Both slices of the fat binary contain this firmware; use the first.
    firmware = bluetool[392122:392122 + 17249]
    require_hash(firmware, '6d24776498af7d040ac254dbca1bb5998c0aadc525ffd26c8a4f1c07eb36d57f', 'N81 HCD')
    off = records = 0
    while off < len(firmware):
        if off + 3 > len(firmware):
            raise ValueError('Truncated HCD header')
        off += 3 + firmware[off + 2]
        records += 1
    if off != len(firmware) or records != 101:
        raise ValueError('Invalid HCD record boundaries')
    boot = f'''# N81AP 10B500 BlueTool boot sequence, firmware loading changed to external file.
device -D
wake on
reset pulse 100
hci reset
bcm -B
msleep 200
bcm -w /etc/bluetool/{FIRMWARE}
msleep 200
device -s 115200
msleep 200
bcm -B
msleep 200
bcm -A
bcm -N
bcm -s 0x01,0x00,0x00,0x01,0x01,0x00,0x01,0x00,0x00,0x00,0x00,0x01
bcm -r 0x86E01=0x0A
bcm -r 0x815C9=4
bcm -r 0x815CC=3
quit
'''.encode()
    sleep = b'''# N81AP 10B500 BlueTool deepsleep sequence.
device -D -S
wake on
hci reset
bcm -s 0x01,0x00,0x00,0x01,0x01,0x00,0x01,0x00,0x00,0x00,0x00,0x01
wake off
quit
'''
    return {FIRMWARE: firmware, PRODUCT + '.boot.script': boot,
            PRODUCT + '.init.script': b'quit\n', PRODUCT + '.deepsleep.script': sleep}


def patch_kernel(source, target):
    blob = source.read_bytes()
    require_hash(blob, '0742b236a5e9504a3a3d1df8f4773c495f3b8a01ef7576127d590f48ec3ea847', 'linked CS59 kernel')
    macho = MachO(source)
    bridge = json.loads((HERE / 'bridge.json').read_text())
    stub = bytes.fromhex(bridge['hook_bytes'])
    entry, hook = int(bridge['entry'], 16), int(bridge['hook_address'], 16)
    delta = hook - (entry + 4)
    s, i1, i2 = (delta >> 24) & 1, (delta >> 23) & 1, (delta >> 22) & 1
    branch = struct.pack('<HH', 0xf000 | s << 10 | (delta >> 12) & 0x3ff,
                         0x9000 | (1 ^ i1 ^ s) << 13 | (1 ^ i2 ^ s) << 11 | (delta >> 1) & 0x7ff)
    result = bytearray(blob)
    for address, before, after in [(entry, bytes.fromhex('00252428'), branch),
                                    (hook, bytes(len(stub)), stub),
                                    (0x80d3847a, b'mikey\0', b'codec\0')]:
        offset = macho.offset(address)
        if result[offset:offset + len(before)] != before:
            raise ValueError(f'Kernel guard failed at {address:#x}')
        result[offset:offset + len(before)] = after
    require_hash(result, 'c082f2b423e04aa60a71840c573557d9564d70542f45468de6c60fc2159ff0a8', 'kernel-only N81 candidate')
    target.write_bytes(result)


def sign_btserver(blob, ldid):
    with tempfile.TemporaryDirectory(prefix='touch4-bt-') as directory:
        executable = Path(directory) / 'BTServer'
        executable.write_bytes(blob)
        entitlements = subprocess.check_output([str(ldid), '-e', str(executable)])
        original = plistlib.loads(entitlements)
        entitlement_file = Path(directory) / 'entitlements.plist'
        entitlement_file.write_bytes(entitlements)
        subprocess.run([str(ldid), '-S' + str(entitlement_file), str(executable)], check=True)
        result = executable.read_bytes()
        signed = plistlib.loads(subprocess.check_output([str(ldid), '-e', str(executable)]))
        if signed != original:
            raise ValueError('BTServer entitlements changed while signing')
        return result


def overlay(target, btserver, bluetool, gestalt, ldid):
    files = {'usr/sbin/BTServer': (sign_btserver(patch_btserver(btserver), ldid), 0o755)}
    files.update({'private/etc/bluetool/' + name: (blob, 0o644)
                  for name, blob in bluetooth_resources(bluetool).items()})
    config = plistlib.loads(gestalt)
    config.setdefault('CacheExtra', {})['bluetooth'] = True
    files['private/var/mobile/Library/Caches/com.apple.MobileGestalt.plist'] = (plistlib.dumps(config), 0o644)
    # Match the already-tested directory repair. The Settings gallery still
    # needs a separate diagnosis; do not describe this as a complete fix.
    links = {}
    for number in list(range(101, 128)) + list(range(200, 206)):
        for suffix in ['@2x', '.thumbnail@2x']:
            links[f'{number}{suffix}~ipod.png'] = f'../iPhone/{number}{suffix}~iphone.png'
    links['default@2x.png'] = '../iPhone/default@2x.png'
    with tarfile.open(target, 'w', format=tarfile.USTAR_FORMAT) as archive:
        # hfsplus untar needs parent directories, ordered before their children.
        dirs = {'Library/Wallpaper/iPod'}
        for name in files:
            dirs.update(str(p) for p in Path(name).parents if str(p) != '.')
        dirs.update(['Library', 'Library/Wallpaper'])
        for name in sorted(dirs, key=lambda n: (n.count('/'), n)):
            info = tarfile.TarInfo(name)
            info.type, info.mode = tarfile.DIRTYPE, 0o755
            if name == 'private/var/mobile' or name.startswith('private/var/mobile/'):
                info.uid = info.gid = 501
            archive.addfile(info)
        for name, (blob, mode) in sorted(files.items()):
            info = tarfile.TarInfo(name)
            info.size, info.mode = len(blob), mode
            if '/mobile/' in name:
                info.uid = info.gid = 501
            archive.addfile(info, io.BytesIO(blob))
        for name, link in sorted(links.items()):
            info = tarfile.TarInfo('Library/Wallpaper/iPod/' + name)
            info.type, info.mode, info.linkname = tarfile.SYMTYPE, 0o777, link
            archive.addfile(info)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='command', required=True)
    kernel = sub.add_parser('kernel')
    for arg in ['input', 'kext', 'output', 'xpwntool']:
        kernel.add_argument('--' + arg, type=Path, required=True)
    rootfs = sub.add_parser('overlay')
    for arg in ['btserver', 'bluetool', 'gestalt', 'output', 'ldid']:
        rootfs.add_argument('--' + arg, type=Path, required=True)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    if args.command == 'overlay':
        overlay(args.output / 'rootfs.tar', args.btserver.read_bytes(),
                args.bluetool.read_bytes(), args.gestalt.read_bytes(), args.ldid)
        return
    raw = args.output / 'kernel.original.macho'
    subprocess.run([str(args.xpwntool), str(args.input), str(raw)], check=True)
    subprocess.run([sys.executable, str(HERE / 'link_audio.py'), '--kernel', str(raw),
                    '--kext', str(args.kext), '--output', str(args.output)], check=True)
    patched = args.output / 'kernel.n81.macho'
    patch_kernel(args.output / 'kernel.cs59.macho', patched)
    img = args.output / 'kernelcache'
    subprocess.run([str(args.xpwntool), str(patched), str(img), '-t', str(args.input)], check=True)
    check = args.output / 'kernel.roundtrip.macho'
    subprocess.run([str(args.xpwntool), str(img), str(check)], check=True)
    if check.read_bytes() != patched.read_bytes():
        raise ValueError('Kernel Img3 round trip failed')


if __name__ == '__main__':
    main()
