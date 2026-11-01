#!/usr/bin/env python3
"""Receive-only DCSD logging. Never sends serial bytes or device commands."""
import argparse
import datetime
import errno
import fcntl
import hashlib
import os
from pathlib import Path
import select
import signal
import termios
import tempfile
import time

from prepare import write_json


def ports():
    if os.uname().sysname == "Darwin":
        return sorted(str(p) for p in Path('/dev').glob('cu.usbserial-*'))
    root = Path('/dev/serial/by-id')
    return sorted(str(p) for p in root.glob('*') if any(s in p.name.lower() for s in ('ftdi', 'dcsd')))


def configure(fd):
    original = termios.tcgetattr(fd)
    value = termios.tcgetattr(fd)
    value[0] = value[1] = value[3] = 0
    value[2] &= ~(termios.CSIZE | termios.PARENB | termios.CSTOPB | termios.HUPCL | getattr(termios, 'CRTSCTS', 0))
    value[2] |= termios.CS8 | termios.CREAD | termios.CLOCAL
    value[4] = value[5] = termios.B115200
    value[6][termios.VMIN] = value[6][termios.VTIME] = 0
    termios.tcsetattr(fd, termios.TCSANOW, value)
    return original


def capture(port, directory, duration=0):
    directory = Path(directory)
    directory.mkdir(mode=0o700, parents=True, exist_ok=True)
    status = dict(port=port, baud=115200, received_bytes=0, transmitted_bytes=0,
                  started_utc=datetime.datetime.now(datetime.timezone.utc).isoformat(), state='opening')
    status_path = directory / 'capture.json'
    stopping = [False]
    handlers = {s: signal.signal(s, lambda *_: stopping.__setitem__(0, True))
                for s in (signal.SIGTERM, signal.SIGINT)}
    deadline = time.monotonic() + duration if duration else float('inf')
    lock_fd = None
    try:
        # A host-wide lock also protects reconnect gaps when the port disappears.
        port_name = os.path.realpath(port)
        if os.uname().sysname == 'Darwin':
            port_name = port_name.replace('/dev/tty.', '/dev/cu.', 1)
        key = hashlib.sha256(port_name.encode()).hexdigest()[:24]
        lock_path = Path(tempfile.gettempdir()) / f'lik-dcsd-{os.getuid()}-{key}.lock'
        lock_fd = os.open(str(lock_path), os.O_CREAT | os.O_RDWR | getattr(os, 'O_NOFOLLOW', 0), 0o600)
        try:
            fcntl.flock(lock_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise RuntimeError('Another DCSD capture already owns this port; stop that capture before restoring')
        with (directory / 'serial.bin').open('xb') as raw, (directory / 'serial.log').open('x') as log:
            while not stopping[0] and time.monotonic() < deadline:
                fd, original = None, None
                try:
                    fd = os.open(port, os.O_RDONLY | os.O_NOCTTY | os.O_NONBLOCK)
                    fcntl.ioctl(fd, termios.TIOCEXCL)
                    original = configure(fd)
                    status.update(state='listening', error=None)
                    write_json(status_path, status)
                    while not stopping[0] and time.monotonic() < deadline:
                        if not select.select([fd], [], [], 0.25)[0]:
                            continue
                        data = os.read(fd, 65536)
                        if not data:
                            time.sleep(0.05)
                            continue
                        raw.write(data)
                        raw.flush()
                        status['received_bytes'] += len(data)
                        stamp = datetime.datetime.now(datetime.timezone.utc).isoformat()
                        log.write('\n[' + stamp + '] ' + data.decode('utf-8', errors='backslashreplace'))
                        log.flush()
                        if status['received_bytes'] >= 64 * 1024**2:
                            raise RuntimeError('Serial capture reached its 64 MiB limit')
                except OSError as exc:
                    status.update(state='waiting-for-port', error=str(exc))
                    write_json(status_path, status)
                    if exc.errno not in (errno.ENODEV, errno.ENOENT, errno.EIO, errno.ENXIO):
                        raise
                    time.sleep(0.5)
                finally:
                    if fd is not None:
                        if original is not None:
                            try:
                                termios.tcsetattr(fd, termios.TCSANOW, original)
                            except (OSError, termios.error):
                                pass
                        try:
                            fcntl.ioctl(fd, termios.TIOCNXCL)
                        except OSError:
                            pass
                        os.close(fd)
        status['state'] = 'stopped'
    except Exception as exc:
        status.update(state='failed', error=str(exc))
        raise
    finally:
        if lock_fd is not None:
            os.close(lock_fd)
        write_json(status_path, status)
        for sig, handler in handlers.items():
            signal.signal(sig, handler)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--list-ports', action='store_true')
    parser.add_argument('--port')
    parser.add_argument('--directory')
    parser.add_argument('--duration', type=float, default=0)
    args = parser.parse_args()
    if args.list_ports:
        print('\n'.join(ports()))
    elif args.port and args.directory:
        os.umask(0o077)
        capture(args.port, args.directory, args.duration)
    else:
        parser.error('--port and --directory are required for capture')
