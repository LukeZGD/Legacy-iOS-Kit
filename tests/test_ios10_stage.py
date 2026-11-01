"""Offline tests of private-runtime isolation and per-restore credentials."""

import hashlib
import io
import json
from pathlib import Path
import plistlib
import struct
import subprocess
import sys
import tarfile
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "resources/ios10"))
import stage
from macho import ImageError, check_or_update_hashes, commands, unpack, relocate_dylibs
from prepare import validate_stage


class StageTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.files, cls.report, cls.manifest = stage.runtime_files(ROOT / "resources")

    def test_runtime_relocates_nonstock_libraries_and_repairs_code_hashes(self):
        for name in stage.LIBRARIES:
            self.assertIn("usr/lik/" + name, self.files)
        for name, (data, mode) in self.files.items():
            if not name.startswith("usr/lik/"):
                continue
            check_or_update_hashes(data)
            for cmd, pos, size in commands(data):
                if cmd in (0xC, 0xD, 0x80000018, 0x8000001F):
                    off = unpack("<I", data, pos + 8)[0]
                    dependency = data[pos + off:pos + size].split(b"\0")[0].decode()
                    self.assertNotIn(dependency, ["/usr/lib/" + lib for lib in stage.LIBRARIES])
                    if dependency.startswith("/usr/lik/"):
                        self.assertIn(dependency.lstrip("/"), self.files)

    def test_oversized_dylib_name_and_corrupted_source_are_rejected(self):
        original = stage.archive_file(ROOT / "resources/jailbreak/openssh.tar.gz", "usr/sbin/sshd")
        with self.assertRaisesRegex(ImageError, "exceeds"):
            relocate_dylibs(original, {"/usr/lib/libcrypto.0.9.8.dylib": "/" + "a" * 300})
        changed = bytearray(original)
        changed[4096] ^= 1
        with self.assertRaisesRegex(ImageError, "code hash"):
            relocate_dylibs(changed, {})

    def test_stage_has_no_client_private_key_or_live_procyon_trigger(self):
        def fake_keygen(path, comment):
            path.write_text("PRIVATE-" + path.name)
            path.chmod(0o600)
            path.with_suffix(".pub").write_text("ssh-rsa PUBLIC-" + path.name + " comment\n")
            return "ssh-rsa PUBLIC-" + path.name

        with tempfile.TemporaryDirectory() as tmp, patch.object(stage, "keygen", fake_keygen):
            session = Path(tmp) / "session"
            info = stage.create_session(session, "iPhone5,4", "n49ap", "10.3.4", "14G61", "12345")
            self.assertEqual(session.stat().st_mode & 0o777, 0o700)
            entries = validate_stage(session / "stage.tar")
            self.assertFalse(any(n.startswith(("var/", "private/", "etc/")) for n in entries))
            self.assertEqual({n for n,v in entries.items() if n.startswith("System/") and v is not None}, set())
            with tarfile.open(session / "stage.tar") as t:
                for m in t:
                    self.assertEqual((m.uid, m.gid), (0, 0))
                    if m.isfile():
                        self.assertNotIn(b"PRIVATE-client_rsa", t.extractfile(m).read())
                self.assertTrue(all(n == "Applications" or n.startswith("Applications/LIKTools.app") for n in t.getnames()))
                self.assertNotIn("bin/sh", t.getnames())
                self.assertNotIn("usr/lik", t.getnames())
                embedded = t.extractfile("Applications/LIKTools.app/runtime.tar").read()
                self.assertEqual(embedded, (session / "runtime.tar").read_bytes())
                self.assertEqual(t.extractfile("Applications/LIKTools.app/runtime.sha256").read().strip().decode(), hashlib.sha256(embedded).hexdigest())
            with tarfile.open(session / "runtime.tar") as t:
                base = stage.DEVICE.lstrip("/") + "/"
                self.assertEqual(t.getmember(base + "host_rsa").mode, 0o600)
                self.assertEqual(t.getmember("bin/sh").linkname, "/usr/lik/bash")
                config = t.extractfile(base + "sshd_config").read().decode()
                self.assertEqual(t.extractfile(base + "identity").read().decode().splitlines()[1:],
                                 ["iPhone5,4", "n49ap", "10.3.4", "14G61", "12345"])
                for option in ("ListenAddress 127.0.0.1", "PasswordAuthentication no",
                               "ForceCommand /usr/lik/bash " + stage.DEVICE + "/transport.sh"):
                    self.assertIn(option, config)
                daemon = plistlib.loads(t.extractfile("Library/LaunchDaemons/" + stage.DAEMON + ".plist").read())
                self.assertEqual(daemon["KeepAlive"], {"SuccessfulExit": False})
                self.assertIn("/var/root/lik-ios10/" + info['session'] + "/ssh-selftest.pub", config)
                self.assertNotIn(base + 'diagnostic-helper', t.getnames())
                self.assertNotIn(base + 'ondevice-install.plist', t.getnames())
                self.assertTrue(t.getmember(base + 'local-install.sh').isfile())

                self.assertEqual(daemon["ThrottleInterval"], 15)
                self.assertTrue(daemon["RunAtLoad"])
                for job in ("bootstrap", "untether"):
                    self.assertFalse(plistlib.loads(t.extractfile(base + job + ".plist").read())["KeepAlive"])
                self.assertNotIn("Library/LaunchDaemons/org.legacyioskit.ios10.bootstrap.plist", t.getnames())
            self.assertIn("lik-ios10-" + info["session"], (session / "known_hosts").read_text())
            with self.assertRaises(FileExistsError):
                stage.create_session(session, "iPhone5,4", "n49ap", "10.3.4", "14G61", "12345")

    def test_device_script_accepts_both_5c_14g61_identities(self):
        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp)
            script = ROOT / "resources/ios10/device/common.sh"
            for product, board in (("iPhone5,3", "n48ap"), ("iPhone5,4", "n49ap")):
                (directory / "identity").write_text("01234567-0123-4567-89ab-0123456789ab\n"
                                                  + product + "\n" + board + "\n10.3.4\n14G61\n12345\n")
                result = subprocess.run(["/bin/bash", "--noprofile", "--norc", "-c",
                    'source "$1"; D="$2"; read_identity; printf "%s:%s" "$PRODUCT" "$BUILD"',
                    "identity-test", str(script), str(directory)], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout.decode(), product + ":14G61")

    def test_stage_rejects_stock_library_replacement_and_parent_symlinks(self):
        for name, kind, target in (("usr/lib/libSystem.B.dylib", tarfile.REGTYPE, ""),
                                   ("usr/lik", tarfile.SYMTYPE, "/usr/lib"),
                                   ("bin/sh", tarfile.SYMTYPE, "/private/var/payload"),
                                   ("usr", tarfile.REGTYPE, "")):
            with self.subTest(name=name), tempfile.TemporaryDirectory() as tmp:
                p = Path(tmp) / "bad.tar"
                with tarfile.open(p, "w") as t:
                    m = tarfile.TarInfo(name)
                    m.mode, m.type, m.linkname = 0o755, kind, target
                    t.addfile(m, io.BytesIO())
                with self.assertRaises(ImageError):
                    validate_stage(p)

    def test_invalid_ecid_rejected_before_creating_any_session(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "session"
            for ecid in ("0", "-1", "0x123", "1\ncommand", str(2**64)):
                with self.assertRaises(ImageError):
                    stage.create_session(path, "iPhone5,3", "n48ap", "10.3.3", "14G60", ecid)
                self.assertFalse(path.exists())


if __name__ == "__main__":
    unittest.main()
