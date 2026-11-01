import json
import os
import plistlib
import re
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'resources/ios10'))
from allinone_stage import bootstrap_status, compose, file_entry, read_tar
from macho import ImageError


class MetadataTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.files, _ = compose(dict(product='iPhone5,4', board='n49ap',
            version='10.3.4', build='14G61', session='metadata-regression'))
        cls.bootstrap = read_tar((ROOT / 'resources/ios10/assets/bootstrap.tar').read_bytes())

    def test_final_status_is_complete_without_changing_existing_states(self):
        plan = plistlib.loads(self.files['usr/local/share/lik-aio/plan.plist'][1])
        entry = plan['final_data'][0]
        status = self.files['usr/local/share/lik-aio/data/' + entry['blob']][1].decode()
        records = {}
        for stanza in status.strip().split('\n\n'):
            fields = dict(re.findall(r'^([^ :]+): (.*)$', stanza, re.M))
            self.assertIn('Status', fields, fields['Package'])
            self.assertNotIn(fields['Package'], records)
            records[fields['Package']] = fields
        self.assertEqual(records['firmware']['Version'], '10.3.4')
        for package in ('uikittools', 'com.saurik.patcyh'):
            self.assertEqual(records[package]['Status'], 'install ok installed')
        original = self.bootstrap['private/var/lib/dpkg/status'][1].decode()
        for stanza in original.strip().split('\n\n'):
            fields = dict(re.findall(r'^([^ :]+): (.*)$', stanza, re.M))
            if 'Status' in fields:
                self.assertEqual(records[fields['Package']]['Status'], fields['Status'])

    def test_missing_payload_is_not_claimed_installed(self):
        for path in ('private/var/lib/dpkg/info/uikittools.list', 'usr/bin/uicache',
                     'usr/lib/libpatcyh.dylib'):
            with self.subTest(path=path):
                files = dict(self.bootstrap)
                del files[path]
                with self.assertRaises(ImageError):
                    bootstrap_status(files)

    def test_explicit_uninstalled_state_is_preserved(self):
        files = dict(self.bootstrap)
        m, data = files['private/var/lib/dpkg/status']
        data = data.replace(b'Package: uikittools\n',
                            b'Package: uikittools\nStatus: deinstall ok config-files\n')
        files['private/var/lib/dpkg/status'] = (m, data)
        result = bootstrap_status(files)
        self.assertIn('Package: uikittools\nStatus: deinstall ok config-files\n', result)

    def test_only_bootstrap_job_can_start_metadata(self):
        jobs = [plistlib.loads(data) for name, (_, data) in self.files.items()
                if name.startswith('Library/LaunchDaemons/') and name.endswith('.plist')]
        owners = [job for job in jobs if any('cydia/startup' in arg or 'metadata.sh' in arg
                  for arg in job.get('ProgramArguments', []))]
        self.assertEqual([job['Label'] for job in owners], ['com.saurik.Cydia.Startup'])
        self.assertEqual(owners[0]['StandardErrorPath'], '/var/log/lik-ios10-metadata.log')

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.bin = self.root / 'test-bin'
        self.bin.mkdir()
        for directory in ('var/root/Media/Cydia/AutoInstall', 'var/lib/cydia',
                          'var/mobile/Media/LegacyiOSKitLogs', 'usr/libexec/cydia',
                          'usr/local/share/lik-aio'):
            (self.root / directory).mkdir(parents=True, exist_ok=True)
        (self.root / 'var/root/lik-aio-installed').write_text('restore complete\n')
        self.trace = self.root / 'trace'
        self.trace.write_text('')
        self.marker = self.root / 'var/root/lik-aio-metadata-complete'
        self.receipt = self.root / 'var/mobile/Media/LegacyiOSKitLogs/first-boot.txt'
        self.env = dict(os.environ, PATH=str(self.bin) + ':/usr/bin:/bin',
                        TRACE=str(self.trace), FIXTURE_ROOT=str(self.root))
        self.executable(self.root / 'usr/libexec/cydia/firmware.sh', '''#!/bin/bash
printf 'firmware\n' >> "$TRACE"
[[ ${FIRMWARE_RESULT:-0} == 0 ]] || exit "$FIRMWARE_RESULT"
echo 6 > "$FIXTURE_ROOT/var/lib/cydia/firmware.ver"
''')
        self.executable(self.bin / 'su', '''#!/bin/bash
[[ $# == 3 && $1 == -c && $3 == mobile ]] || exit 90
[[ $2 == uicache || $2 == /usr/bin/uicache ]] || exit 91
printf 'icons\n' >> "$TRACE"
exit "${ICON_RESULT:-0}"
''')
        for command in ('sbdidlaunch', 'dpkg', 'killall', 'chown'):
            self.executable(self.bin / command,
                            '#!/bin/bash\nprintf "' + command + '\\n" >> "$TRACE"\n')
        for path in ('usr/libexec/cydia/startup', 'usr/local/share/lik-aio/metadata.sh'):
            text = self.files[path][1].decode()
            for prefix in ('/usr/libexec/cydia', '/usr/local/share/lik-aio',
                           '/var/root', '/var/lib/cydia', '/var/mobile'):
                text = text.replace(prefix, str(self.root) + prefix)
            text = text.replace('/bin/su', str(self.bin / 'su'))
            text = text.replace('export PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin',
                                'export PATH=' + str(self.bin) + ':/usr/bin:/bin')
            self.executable(self.root / path, text)

    def executable(self, path, content):
        path.write_text(content)
        path.chmod(0o755)

    def run_startup(self, **env):
        result = subprocess.run(['/bin/bash', str(self.root / 'usr/libexec/cydia/startup')],
                                env=dict(self.env, **env), capture_output=True, text=True,
                                timeout=10)
        return result, self.trace.read_text().splitlines()

    def test_success_and_subsequent_boot_keep_one_metadata_owner(self):
        result, trace = self.run_startup()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(trace.count('firmware'), 1)
        self.assertTrue(self.marker.exists())
        self.assertEqual(self.receipt.read_bytes(), self.marker.read_bytes())
        self.trace.write_text('')
        result, trace = self.run_startup()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(trace, ['firmware'])

    def test_firmware_failure_stops_before_icons_or_completion(self):
        result, trace = self.run_startup(FIRMWARE_RESULT='7')
        self.assertEqual(result.returncode, 7)
        self.assertEqual(trace, ['firmware'])
        self.assertFalse(self.marker.exists())
        self.assertFalse(self.receipt.exists())

    def test_icon_failure_can_retry_on_next_boot(self):
        result, trace = self.run_startup(ICON_RESULT='9')
        self.assertEqual(result.returncode, 9)
        self.assertFalse(self.marker.exists())
        self.assertFalse(self.receipt.exists())
        self.trace.write_text('')
        result, trace = self.run_startup()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(trace.count('firmware'), 1)
        self.assertTrue(self.marker.exists())
        self.assertTrue(self.receipt.exists())

    def test_bootstrap_autoinstall_still_runs(self):
        package = self.root / 'var/root/Media/Cydia/AutoInstall/fixture.deb'
        package.write_text('fixture')
        result, trace = self.run_startup()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('dpkg', trace)
        self.assertFalse(package.exists())
        self.assertTrue(self.receipt.exists())


if __name__ == '__main__':
    unittest.main()
