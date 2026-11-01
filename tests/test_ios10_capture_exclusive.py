import json
import os
from pathlib import Path
import pty
import subprocess
import sys
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]


class CaptureExclusivityTests(unittest.TestCase):
    def test_second_capture_is_rejected_and_lock_releases_after_stop(self):
        master, slave = pty.openpty()
        processes = []
        try:
            with tempfile.TemporaryDirectory() as tmp:
                def start(name):
                    folder = Path(tmp) / name
                    p = subprocess.Popen([sys.executable,
                        str(ROOT / 'resources/ios10/serial_capture.py'),
                        '--port', os.ttyname(slave), '--directory', str(folder)],
                        stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                    processes.append(p)
                    deadline = time.monotonic() + 5
                    while time.monotonic() < deadline:
                        status = folder / 'capture.json'
                        if status.exists():
                            data = json.loads(status.read_text())
                            if data['state'] in ('listening', 'failed'):
                                return p, data
                        if p.poll() is not None:
                            self.fail(p.communicate()[1].decode())
                        time.sleep(.02)
                    self.fail('Capture did not report its state')

                first, status = start('first')
                self.assertEqual(status['state'], 'listening')
                second, status = start('second')
                self.assertEqual(status['state'], 'failed')
                self.assertIn('already owns this port', status['error'])
                second.communicate(timeout=5)
                self.assertNotEqual(second.returncode, 0)
                self.assertIsNone(first.poll())
                first.terminate(); first.communicate(timeout=5)
                self.assertEqual(first.returncode, 0)
                third, status = start('third')
                self.assertEqual(status['state'], 'listening')
                third.terminate(); third.communicate(timeout=5)
                self.assertEqual(third.returncode, 0)
        finally:
            for p in processes:
                if p.poll() is None:
                    p.kill(); p.communicate(timeout=5)
            os.close(master); os.close(slave)
