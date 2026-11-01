"""Host continuation tests without SSH, USB, firmware restore, or root access."""

import copy
import io
import json
from pathlib import Path
import plistlib
import sys
import subprocess
import tarfile
import tempfile
import unittest
import zipfile
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "resources/ios10"))
from macho import ImageError
import session as host

IDENTITY = dict(schema=1, session="01234567-0123-4567-89ab-0123456789ab", ecid="12345",
                product="iPhone5,4", board="n49ap", version="10.3.4", build="14G61")


def archive(files):
    data = io.BytesIO()
    with tarfile.open(fileobj=data, mode="w") as tar:
        for name, value in files.items():
            m = tarfile.TarInfo(name)
            if isinstance(value, tuple):
                m.type, m.linkname = tarfile.SYMTYPE, value[0]
                tar.addfile(m)
            else:
                m.size = len(value)
                tar.addfile(m, io.BytesIO(value))
    return data.getvalue()


def captures():
    before = {"etc/racoon/racoon.conf": b"stock racoon", "usr/libexec/backboardd": b"stock backboard",
              "usr/libexec/wifiFirmwareLoaderLegacy": b"stock wifi",
              "var/db/com.apple.xpc.launchd/disabled.plist": b"stock disabled"}
    after = {"var/root/procyon/backup/" + Path(n).name: b for n, b in before.items()}
    after.update({"usr/libexec/wifiFirmwareLoaderLegacy": ("/usr/sbin/racoon",),
                  "var/db/com.apple.xpc.launchd/disabled.plist": (ROOT / "resources/ios10/assets/procyon-disabled.plist").read_bytes(),
                  "var/lib/dpkg/info/com.staturnz.procyon.postinst": (ROOT / "resources/ios10/assets/procyon-postinst").read_bytes(),
                  "etc/racoon/stage2": b"generated stage2", "var/root/procyon/stage3.bin": b"generated stage3",
                  "var/root/procyon/stage1/part1.conf": b"generated part1"})
    return before, after


class FakeSSH:
    def __init__(self, session, fail_untether=False, fail_upload=False, cold_patched=False):
        self.session, self.calls = session, []
        self.phase, self.boot = "new", "boot1"
        self.fail_untether, self.fail_upload, self.cold_patched = fail_untether, fail_upload, cold_patched
        self.settings = b""

    def info(self):
        return dict(self.session.data, uid="0", phase=self.phase, boot=self.boot,
                    bootargs="lik_ios10_jumpstart=1" if self.boot == "boot1" or self.cold_patched else "")

    def run(self, operation, data=None, **kwargs):
        self.calls.append(operation)
        if operation == "start-bootstrap":
            self.phase = "needs-settings"
        elif operation == "get-settings":
            return plistlib.dumps({"UnrelatedSetting": 42}, fmt=plistlib.FMT_BINARY)
        elif operation == "put-settings":
            self.settings = data
        elif operation == "get-staged-settings":
            return self.settings + (b"broken" if self.fail_upload else b"")
        elif operation == "apply-settings":
            self.phase = "settings-ready"
        elif operation == "start-untether":
            self.phase = "untether-failed" if self.fail_untether else "untether-installed"
        elif operation in ("before-capture", "after-capture"):
            return archive(captures()[0 if operation == "before-capture" else 1])
        elif operation == "reboot":
            self.boot = "boot2"
        elif operation == "cold-boot-proof":
            return b"uid=0\nboot=boot2\n123 /System/Library/CoreServices/SpringBoard.app/SpringBoard\n"
        return b""


class SessionTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.directory = Path(self.tmp.name)
        self.directory.chmod(0o700)
        self.data = dict(IDENTITY, phase="awaiting-jumpstart")
        (self.directory / "session.json").write_text(json.dumps(self.data))
        self.session = host.Session(self.directory)

    def tearDown(self):
        self.tmp.cleanup()

    def test_space_check_uses_extracted_size_on_actual_working_volume(self):
        image = self.directory / 'custom.ipsw'
        with zipfile.ZipFile(image, 'w', compression=zipfile.ZIP_DEFLATED) as archive:
            archive.writestr('root.dmg', b'0' * 1024**2)
        record = self.directory / 'preparation.json'
        record.write_text(json.dumps({'components': {'OS': {'path': 'root.dmg'}}}))
        self.session.data.update(image=str(image), preparation=str(record), preparation_sha256=host.digest(record))
        workdir = self.directory / 'actual-restorer-directory'
        workdir.mkdir()
        required = 513 * 1024**2
        with patch.object(host.shutil, 'disk_usage') as usage:
            usage.return_value.free = required - 1
            with self.assertRaisesRegex(ImageError, 'Not enough free space'):
                self.session.check_space(workdir)
            usage.assert_called_with(workdir.resolve())
            usage.return_value.free = required
            self.assertEqual(self.session.check_space(workdir)['required_bytes'], required)

    def test_failed_restore_never_advances_to_jumpstart(self):
        self.session.data["phase"] = "restore-running"
        self.session.restore_result(9)
        self.assertEqual(host.Session(self.directory).data["phase"], "restore-failed")
        ssh = FakeSSH(self.session)
        with self.assertRaises(ImageError):
            host.continue_install(self.session, ssh)
        self.assertEqual(ssh.calls, [])

    def test_only_successful_restore_can_request_jumpstart(self):
        self.session.data["phase"] = "image-ready"
        with self.assertRaises(ImageError):
            self.session.restore_result(0)
        self.session.transition("restore-running")
        self.session.restore_result(0)
        self.assertEqual(self.session.data["phase"], "awaiting-jumpstart")

    def test_recovery_identity_must_match_ecid_and_board(self):
        good = "ECID: 0x3039\nPRODUCT: iPhone5,4\nMODEL: n49ap\nMODE: DFU\n"
        self.session.verify_recovery_identity(good)
        for changed in (good.replace("3039", "3040"), good.replace("n49ap", "n48ap"),
                        good.replace("5,4", "5,2"), "ERROR: device not found"):
            with self.assertRaises(ImageError):
                self.session.verify_recovery_identity(changed)

    def test_booted_identity_rejects_forged_or_duplicate_fields(self):
        values = {k: str(v) for k, v in IDENTITY.items() if k != "schema"}
        values.update(uid="0", phase="new", boot="boot1", bootargs="lik_ios10_jumpstart=1")
        raw = "".join(k + "=" + v + "\n" for k, v in values.items()).encode()
        host.parse_info(raw, self.session)
        for changed in (raw.replace(b"uid=0", b"uid=501"), raw.replace(b"product=iPhone5,4", b"product=iPhone5,2"),
                        raw + b"phase=untether-installed\n"):
            with self.assertRaises(ImageError):
                host.parse_info(changed, self.session)

    def test_settings_preserve_other_keys_and_binary_format(self):
        original = plistlib.dumps({"keep": [1, 2], "SBShowNonDefaultSystemApps": False}, fmt=plistlib.FMT_BINARY)
        new = host.springboard_settings(original)
        self.assertTrue(new.startswith(b"bplist"))
        self.assertEqual(plistlib.loads(new), {"keep": [1, 2], "SBShowNonDefaultSystemApps": True})
        for bad in (b"not a plist", plistlib.dumps(["not a dict"]), b"x" * (2 * 1024**2 + 1)):
            with self.assertRaises(ImageError):
                host.springboard_settings(bad)

    def test_capture_verifies_backup_trigger_and_service_gating(self):
        before, after = captures()
        host.verify_captures(archive(before), archive(after))
        for key, value in (("var/root/procyon/backup/backboardd", b"wrong"),
                           ("usr/libexec/wifiFirmwareLoaderLegacy", ("/wrong",)),
                           ("var/db/com.apple.xpc.launchd/disabled.plist", b"not disabled")):
            bad = dict(after)
            bad[key] = value
            with self.assertRaises(ImageError):
                host.verify_captures(archive(before), archive(bad))

    def test_full_mock_flow_requires_ordinary_boot_and_springboard(self):
        ssh = FakeSSH(self.session)
        with patch.object(host.time, "sleep"):
            host.continue_install(self.session, ssh)
        self.assertEqual(self.session.data["phase"], "coldboot-verified")
        self.assertTrue((self.directory / "before.tar").is_file())
        self.assertTrue((self.directory / "cold-boot-proof.txt").is_file())
        self.assertLess(ssh.calls.index("after-capture"), ssh.calls.index("reboot"))
        self.assertEqual(plistlib.loads(ssh.settings)["UnrelatedSetting"], 42)

    def test_untether_failure_does_not_reboot_or_report_success(self):
        ssh = FakeSSH(self.session, fail_untether=True)
        with self.assertRaises(ImageError), patch.object(host.time, "sleep"):
            host.continue_install(self.session, ssh)
        self.assertEqual(self.session.data["phase"], "installing")
        self.assertNotIn("reboot", ssh.calls)
        self.assertNotIn("arm-cold-boot", ssh.calls)

    def test_bad_settings_upload_does_not_apply_or_install_untether(self):
        ssh = FakeSSH(self.session, fail_upload=True)
        with self.assertRaises(ImageError), patch.object(host.time, "sleep"):
            host.continue_install(self.session, ssh)
        self.assertNotIn("apply-settings", ssh.calls)
        self.assertNotIn("start-untether", ssh.calls)

    def test_another_patched_boot_is_not_mistaken_for_an_untether(self):
        ssh = FakeSSH(self.session, cold_patched=True)
        with self.assertRaisesRegex(ImageError, "not an untether test"), patch.object(host.time, "sleep"):
            host.continue_install(self.session, ssh)
        self.assertEqual(self.session.data["phase"], "awaiting-coldboot")

    def test_resume_after_journaling_coldboot_retries_only_the_armed_reboot(self):
        self.session.data.update(phase="awaiting-coldboot", pre_cold_boot="boot1")
        ssh = FakeSSH(self.session)
        ssh.phase = "untether-installed"
        with patch.object(host.time, "sleep"):
            host.continue_install(self.session, ssh)
        self.assertEqual(self.session.data["phase"], "coldboot-verified")
        self.assertEqual(ssh.calls, ["reboot", "cold-boot-proof"])

    def test_ssh_uses_session_keys_and_never_disables_host_verification(self):
        argv = host.SSH(self.session, 1234).argv("info")
        self.assertIn("StrictHostKeyChecking=yes", argv)
        self.assertIn("IdentitiesOnly=yes", argv)
        self.assertIn(str((self.directory / "client_rsa").resolve()), argv)
        self.assertIn("HostKeyAlias=lik-ios10-" + IDENTITY["session"], argv)
        with self.assertRaises(ImageError):
            host.SSH(self.session, 1234).argv("info; reboot")

    def test_old_macos_and_modern_ssh_use_compatible_rsa_options(self):
        for version in ("6.9", "7.1", "8.4", "8.5", "9.9", "10.0"):
            output = subprocess.CompletedProcess([], 0, ("OpenSSH_" + version + "p1, test\n").encode())
            with self.subTest(version=version), patch.object(host.subprocess, "run", return_value=output):
                argv = host.SSH(self.session, 1234, "/test/kit/ssh").argv("info")
                self.assertEqual(argv[0], "/test/kit/ssh")
                self.assertIn("HostKeyAlgorithms=ssh-rsa", argv)
                self.assertEqual("PubkeyAcceptedAlgorithms=+ssh-rsa" in argv,
                                 tuple(map(int, version.split("."))) >= (8, 5))

    def test_normal_identity_records_actual_source_build_and_rejects_other_phone(self):
        normal = dict(ProductType="iPhone5,4", HardwareModel="N49AP", UniqueChipID=12345,
                      ProductVersion="10.3.4", BuildVersion="14G61", UniqueDeviceID="a" * 40)
        self.session.bind_normal_identity(plistlib.dumps(normal))
        self.assertEqual(self.session.data["source_build"], "14G61")
        for field, value in (("ProductType", "iPhone5,3"), ("HardwareModel", "N48AP"),
                              ("UniqueChipID", 67890), ("UniqueDeviceID", "invalid")):
            with self.subTest(field=field), self.assertRaises(ImageError):
                self.session.bind_normal_identity(plistlib.dumps(dict(normal, **{field: value})))


if __name__ == "__main__":
    unittest.main()
