import json
import os
from pathlib import Path
import plistlib
import pty
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'resources/ios10'))
from memory import ram_workspace, GIB
from macho import ImageError
from ticket_audit import audit, audit_logs


class DiagnosticsTests(unittest.TestCase):
    def test_raw_serial_evidence_completes_host_ticket_audit(self):
        with tempfile.TemporaryDirectory() as tmp:
            log, serial = Path(tmp) / 'restore.log', Path(tmp) / 'serial.bin'
            log.write_text('Unable to connect to ASR client\n')
            serial.write_bytes(b'received valid ticket (2760 bytes)\nAMFI: code signature validation failed.\n'
                               b'/usr/sbin/asr was terminated by signal 9\n')
            result = audit_logs(log, serial)
            self.assertTrue(result['ticket_accepted'])
            self.assertTrue(result['asr_killed_signal_9'])
            self.assertTrue(result['amfi_signature_rejection'])
            self.assertEqual(result['evidence_sources'], [str(log), str(serial)])

    def test_ticket_audit_requires_explicit_acceptance_or_rejection(self):
        self.assertIsNone(audit('Getting ApNonce in DFU mode... 01 02')['ticket_hashes_match'])
        self.assertFalse(audit('Nonce changed')['ticket_rejected'])
        result = audit('device tree ticket_hash: ' + 'A' * 40 + '\ncomputed ticket_hash: ' + 'B' * 40
                       + '\nramrod_ticket_update: invalid ticket')
        self.assertTrue(result['ticket_rejected'])
        self.assertFalse(result['ticket_hashes_match'])
        result = audit('device tree ticket_hash: ' + 'A' * 40 + '\ncomputed ticket_hash: ' + 'a' * 40
                       + '\nreceived valid ticket (2760 bytes)\nCHECKPOINT BEGIN: RESTORED:[0x060C] partition_nand')
        self.assertTrue(result['ticket_hashes_match'])
        self.assertTrue(result['ticket_accepted'])
        self.assertTrue(result['reached_partition_nand'])

    def test_serial_capture_receives_without_echo_or_transmission(self):
        master, slave = pty.openpty()
        os.set_blocking(master, False)
        try:
            with tempfile.TemporaryDirectory() as tmp:
                folder = Path(tmp)
                proc = subprocess.Popen([sys.executable, str(ROOT / 'resources/ios10/serial_capture.py'),
                                         '--port', os.ttyname(slave), '--directory', tmp, '--duration', '2'],
                                        stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                try:
                    deadline = time.monotonic() + 5
                    while time.monotonic() < deadline:
                        status = folder / 'capture.json'
                        if status.exists() and json.loads(status.read_text())['state'] == 'listening':
                            break
                        if proc.poll() is not None:
                            self.fail(proc.communicate()[1].decode())
                        time.sleep(.02)
                    else:
                        self.fail('Capture did not become ready')
                    data = b'iBEC ticket check\nrestore status\n'
                    os.write(master, data)
                    stdout, stderr = proc.communicate(timeout=5)
                    self.assertEqual(proc.returncode, 0, stderr)
                    self.assertEqual((folder / 'serial.bin').read_bytes(), data)
                    with self.assertRaises(BlockingIOError):
                        os.read(master, 4096)
                    self.assertEqual(json.loads(status.read_text())['transmitted_bytes'], 0)
                finally:
                    if proc.poll() is None:
                        proc.kill()
                        proc.wait()
        finally:
            os.close(master)
            os.close(slave)

    def test_disk_option_never_runs_ram_disk_commands(self):
        with patch('memory.command') as command:
            with ram_workspace(False, '/tmp/fixture') as path:
                self.assertEqual(path, Path('/tmp/fixture'))
            command.assert_not_called()

    def test_mac_ram_disk_detaches_its_own_device_after_build_failure(self):
        with tempfile.TemporaryDirectory() as tmp:
            calls = []
            label = [None]
            def command(*args):
                calls.append(args)
                if args[0].endswith('sysctl'):
                    return str(16 * GIB).encode()
                if 'attach' in args:
                    return b'/dev/disk999\n'
                if 'eraseVolume' in args:
                    label[0] = args[-2]
                if 'info' in args:
                    return plistlib.dumps(dict(MountPoint=tmp, VolumeName=label[0]))
                return b''
            with patch('memory.os.uname') as uname, patch('memory.command', side_effect=command), \
                 patch('memory.shutil.disk_usage') as usage:
                uname.return_value.sysname = 'Darwin'
                usage.return_value.free = 6 * GIB
                with self.assertRaisesRegex(RuntimeError, 'test failure'):
                    with ram_workspace(True, '/unused') as folder:
                        (folder / 'fixture').write_text('temporary')
                        raise RuntimeError('test failure')
                self.assertFalse(folder.exists())
            self.assertEqual(calls[-1], ('/usr/bin/hdiutil', 'detach', '/dev/disk999'))
