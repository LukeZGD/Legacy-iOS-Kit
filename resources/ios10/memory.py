"""Temporary RAM storage for the two large uncompressed HFS images."""
import contextlib
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import tempfile
import uuid

from macho import ImageError

GIB = 1024**3


def command(*args):
    result = subprocess.run(list(args), stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if result.returncode:
        raise ImageError('RAM storage command failed: ' + result.stderr.decode(errors='replace').strip())
    return result.stdout


@contextlib.contextmanager
def ram_workspace(enabled, fallback, required=6 * GIB):
    if not enabled:
        yield Path(fallback)
        return
    device, folder = None, None
    try:
        if os.uname().sysname == 'Darwin':
            total = int(command('/usr/sbin/sysctl', '-n', 'hw.memsize'))
            if total < required + 4 * GIB:
                raise ImageError('RAM option needs at least 10 GiB total memory; select N to build on disk')
            output = command('/usr/bin/hdiutil', 'attach', '-nomount', 'ram://' + str(required // 512)).decode().strip()
            if not re.fullmatch(r'/dev/disk[0-9]+', output):
                raise ImageError('RAM disk attachment returned an unexpected device')
            device = output
            label = 'LIK-' + uuid.uuid4().hex[:12]
            command('/usr/sbin/diskutil', 'eraseVolume', 'HFS+', label, device)
            info = plistlib.loads(command('/usr/sbin/diskutil', 'info', '-plist', device))
            mount = Path(info['MountPoint'])
            if info.get('VolumeName') != label:
                raise ImageError('RAM disk mount identity did not match')
        else:
            mount = Path('/dev/shm')
            mounts = Path('/proc/self/mountinfo').read_text().splitlines()
            if not any(line.split()[4] == '/dev/shm' and ' - tmpfs ' in line for line in mounts):
                raise ImageError('RAM option requires /dev/shm mounted as tmpfs; select N to build on disk')
        if shutil.disk_usage(mount).free < required - 32 * 1024**2:
            raise ImageError('Not enough space in RAM storage; select N to build on disk')
        folder = Path(tempfile.mkdtemp(prefix='ios10-', dir=str(mount)))
        print('Using RAM for uncompressed system images; final IPSW and logs stay on disk.', flush=True)
        yield folder
    finally:
        if folder is not None:
            shutil.rmtree(folder)
        if device is not None:
            # Only the device returned by our RAM attachment is detached.
            command('/usr/bin/hdiutil', 'detach', device)
