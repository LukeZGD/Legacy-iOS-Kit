"""Measured preparation progress, with no device operations or dependencies.

Use the ASCII bar/percentage style of Kit's bundled idevicerestore. That
binary owns its own display; restore.sh has no reusable generic bar function.
"""

import codecs
import errno
import os
from pathlib import Path
import plistlib
import pty
import re
import struct
import subprocess
import sys
import time
import tty


class Progress:
    def __init__(self, label, total, unit="bytes", stream=None):
        self.label, self.total, self.unit = label, max(1, total), unit
        self.stream = stream if stream is not None else sys.stdout
        self.terminal = self.stream.isatty() or (stream is None and os.environ.get("LIK_DIAGNOSTICS_TTY") == "1")
        self.done, self.last_percent, self.last_time = 0, -1, 0

    def __enter__(self):
        print(self.label, file=self.stream, flush=True)
        self.render(0, force=True)
        return self

    def update(self, done):
        self.done = max(self.done, min(self.total, max(0, done)))
        # Finishing the byte/substep count does not prove the operation worked.
        # Only a successful context exit may display 100%.
        self.render(min(99.9, 100 * self.done / self.total))

    def advance(self, amount=1):
        self.update(self.done + amount)

    def render(self, percent, force=False, suffix=""):
        now = time.monotonic()
        if not force:
            if self.terminal:
                if now - self.last_time < 0.1 or percent <= self.last_percent:
                    return
            elif int(percent // 10) <= int(self.last_percent // 10):
                return
        width = 40
        filled = min(width, int(width * percent / 100))
        bar = "[" + "=" * filled + " " * (width - filled) + "] {:5.1f}%".format(percent)
        if self.unit == "steps":
            bar += " ({}/{}, steps)".format(int(self.done), int(self.total))
        end = "\n" if suffix or not self.terminal else ""
        self.stream.write(("\r" if self.terminal else "") + bar + suffix + end)
        self.stream.flush()
        self.last_percent, self.last_time = percent, now

    def __exit__(self, kind, value, traceback):
        if kind is None:
            self.done = self.total
            self.render(100, force=True, suffix="  done")
        else:
            self.render(min(99.9, 100 * self.done / self.total), force=True, suffix="  stopped")


def stream_tool(command, on_line):
    """Read bundled tool output live, including C stdout that otherwise buffers.

    A private PTY makes the tool line-buffer its diagnostics on macOS/Linux.
    It never reads from the user's terminal. Keep the exact output for tools.log.
    """
    master, slave = pty.openpty()
    proc = None
    output = bytearray()
    decoder = codecs.getincrementaldecoder("utf-8")(errors="replace")
    pending = ""
    try:
        tty.setraw(slave)
        proc = subprocess.Popen(command, stdin=subprocess.DEVNULL, stdout=slave,
                                stderr=subprocess.STDOUT, close_fds=True)
        os.close(slave)
        slave = None
        while True:
            try:
                block = os.read(master, 8192)
            except OSError as exc:
                if exc.errno != errno.EIO:
                    raise
                break  # Linux PTY reports EIO when its last writer closes.
            if not block:
                break
            output.extend(block)
            pending += decoder.decode(block)
            while "\n" in pending:
                line, pending = pending.split("\n", 1)
                on_line(line.rstrip("\r"))
        pending += decoder.decode(b"", final=True)
        if pending:
            on_line(pending.rstrip("\r"))
        return subprocess.CompletedProcess(command, proc.wait(), bytes(output))
    finally:
        if slave is not None:
            os.close(slave)
        os.close(master)
        if proc is not None and proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait()


def dmg_extract_size(path):
    """Match dmg extract's first Apple_HFS BLKX, not the whole-disk size.

    UDIF/BLKX offsets follow the bundled tool's xpwn dmg.h. This read is for
    display only; unfamiliar metadata must not alter the existing tool checks.
    """
    try:
        size = Path(path).stat().st_size
        if size < 512:
            return None
        with Path(path).open("rb") as f:
            f.seek(-512, os.SEEK_END)
            trailer = f.read(512)
            if trailer[:4] != b"koly":
                return None
            offset, length = struct.unpack_from(">QQ", trailer, 216)
            if not 0 < length <= 16 * 1024**2 or offset + length > size - 512:
                return None
            f.seek(offset)
            resource = plistlib.loads(f.read(length))
        for entry in resource["resource-fork"]["blkx"]:
            if "Apple_HFS" in entry.get("Name", ""):
                data = entry["Data"]
                if data[:4] != b"mish" or len(data) < 24:
                    return None
                size = struct.unpack_from(">Q", data, 16)[0] * 512
                return size or None
    except Exception:
        # Display metadata must never prevent the existing image tool from
        # handling a format, including plist parser errors on unfamiliar input.
        pass
    return None


class DmgProgress:
    """Consume dmg's actual run offsets/remaining sectors, never elapsed time."""
    def __init__(self, progress, operation):
        self.progress, self.operation = progress, operation
        self.main_partition = False

    def __call__(self, line):
        if self.progress.unit != "bytes":
            return  # Unknown metadata: show one tool step rather than invent bytes.
        if self.operation == "extract":
            match = re.match(r"run \d+: start=(\d+) sectors=", line)
            if match:
                # The diagnostic precedes that run; only earlier bytes are done.
                self.progress.update(int(match.group(1)))
        elif line == "Writing main data blkx...":
            self.main_partition = True
        elif line == "Inserting main blkx...":
            self.main_partition = False
            self.progress.update(self.progress.total)
        elif self.main_partition:
            match = re.match(r"run \d+: (?:skipping )?sectors=\d+, left=(\d+)$", line)
            if match:
                self.progress.update(self.progress.total - int(match.group(1)) * 512)
