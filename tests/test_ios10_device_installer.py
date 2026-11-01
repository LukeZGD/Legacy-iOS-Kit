"""Run the real installer control flow in a rebased temporary filesystem.

All device paths are replaced before execution; dpkg, Procyon, mount and the
runtime are native test doubles. No chroot, root access or device is involved.
"""
import os
from pathlib import Path
import re
import shlex
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class DeviceInstallerTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='lik-device-test-')
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve()
        self.d = self.root / 'usr/local/share/lik-ios10'
        self.r = self.root / 'usr/lik'
        self.j = self.root / 'var/root/lik-ios10/test'
        self.post = self.root / 'var/lib/dpkg/info/com.staturnz.procyon.postinst'
        for p in (self.d, self.r, self.j, self.post.parent, self.root / 'usr/bin', self.root / 'sbin', self.root / 'var/cache'):
            p.mkdir(parents=True, exist_ok=True)
        original = (ROOT / 'resources/ios10/assets/procyon-postinst').read_bytes()
        (self.d / 'procyon-postinst').write_bytes(original)
        for name in ('etc/racoon/racoon.conf', 'usr/libexec/backboardd',
                     'usr/libexec/wifiFirmwareLoaderLegacy', 'var/db/com.apple.xpc.launchd/disabled.plist'):
            p = self.root / name
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text('stock input')
        for name in ('cp', 'mkdir', 'mv', 'rm', 'chmod', 'cat'):
            (self.r / name).symlink_to('/bin/' + name)
        (self.r / 'cmp').symlink_to('/usr/bin/cmp')
        self.executable(self.r / 'sync', 'exit 0\n')
        self.executable(self.r / 'sysctl', 'echo boot1\n')
        self.executable(self.root / 'sbin/mount', 'exit 0\n')
        self.executable(self.root / 'usr/bin/procyon', 'echo procyon >> "$LIK_TEST_TRACE"\nexit "$LIK_TEST_RESULT"\n')
        self.executable(self.root / 'usr/bin/dpkg', r'''
case " $* " in
    *' --unpack '*) cp "$LIK_TEST_D/procyon-postinst" "$LIK_TEST_POST" ;;
    *' --configure '*) /bin/bash "$LIK_TEST_POST" ;;
    *) exit 97 ;;
esac
''')
        app = self.root / 'Applications/LIKTools.app'
        app.mkdir(parents=True)
        self.executable(app / 'LIKTools', 'test "$1" = --socket-configure-untether || exit 98\nexec ' + shlex.quote(str(self.root / 'usr/bin/dpkg')) + ' --force-all --configure com.staturnz.procyon\n')
        common = '\n'.join(k + '=' + shlex.quote(str(v)) for k, v in
                           (('D', self.d), ('R', self.r), ('J', self.j)))
        common += r'''
fail() { echo "FAILED:$*" >&2; exit 1; }
read_identity() { :; }
assert_jumpstart() { :; }
init_journal() { :; }
phase() { cat "$J/phase"; }
write_phase() { printf '%s\n' "$1" > "$J/phase"; }
verify_stage() { :; }
capture() { echo "capture:$1" >> "$LIK_TEST_TRACE"; }
verify_untether() { echo verify >> "$LIK_TEST_TRACE"; return "${LIK_TEST_VERIFY_RESULT:-0}"; }
'''
        (self.d / 'common.sh').write_text(common)
        (self.j / 'phase').write_text('settings-ready\n')
        source = (ROOT / 'resources/ios10/device/install.sh').read_text()
        source = re.sub(r'(?<![A-Za-z0-9_./-])/(?=(?:usr|var|etc|bin|sbin|Applications)/)',
                        str(self.root) + '/', source)
        source = source.replace('[[ -w / ]]', 'true')
        # The test never takes the bootstrap branch; nevertheless redirect its
        # tar destination so no path in this copy can target the host root.
        source = source.replace('-C / ', '-C ' + shlex.quote(str(self.root)) + ' ')
        self.script = self.root / 'install.sh'
        self.script.write_text(source)

    def executable(self, path, body):
        path.write_text('#!/bin/bash\n' + body)
        path.chmod(0o755)

    def run_install(self, code=0, verify=0):
        env = dict(os.environ, LIK_TEST_D=str(self.d), LIK_TEST_POST=str(self.post),
                   LIK_TEST_TRACE=str(self.root / 'trace'), LIK_TEST_RESULT=str(code),
                   LIK_TEST_VERIFY_RESULT=str(verify))
        return subprocess.run(['/bin/bash', str(self.script), 'untether'], env=env,
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10)

    def test_success_restores_original_postinst_and_records_installed(self):
        result = self.run_install()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.j / 'phase').read_text().strip(), 'untether-installed')
        self.assertEqual(self.post.read_bytes(), (self.d / 'procyon-postinst').read_bytes())
        self.assertFalse((self.j / 'lock').exists())
        trace = (self.root / 'trace').read_text().splitlines()
        self.assertEqual(trace, ['capture:before', 'procyon', 'verify', 'capture:after'])

    def test_procyon_failure_is_not_hidden_by_upstream_postinst(self):
        result = self.run_install(code=23)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((self.j / 'procyon-exit-code').read_text().strip(), '23')
        self.assertEqual((self.j / 'phase').read_text().strip(), 'untether-failed')
        self.assertEqual(self.post.read_bytes(), (self.d / 'procyon-postinst').read_bytes())
        self.assertNotIn('capture:after', (self.root / 'trace').read_text())
        self.assertFalse((self.j / 'lock').exists())

    def test_verification_failure_restores_postinst_without_reporting_installed(self):
        result = self.run_install(verify=1)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((self.j / 'phase').read_text().strip(), 'untether-failed')
        self.assertEqual(self.post.read_bytes(), (self.d / 'procyon-postinst').read_bytes())
        self.assertNotIn('capture:after', (self.root / 'trace').read_text())

    def test_existing_lock_stops_before_package_changes_and_is_preserved(self):
        (self.j / 'lock').mkdir()
        result = self.run_install()
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.post.exists())
        self.assertTrue((self.j / 'lock').exists())
        self.assertEqual((self.j / 'phase').read_text().strip(), 'settings-ready')


if __name__ == '__main__':
    unittest.main()
