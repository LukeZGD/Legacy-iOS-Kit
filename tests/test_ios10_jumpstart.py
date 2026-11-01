"""Standalone retry eligibility and DFU transitions; no real USB operations."""
import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest
import uuid

import test_ios10_restore as bridge
from test_ios10_jailbreak_option import ROOT

sys.path.insert(0, str(ROOT / 'resources/ios10'))
import jumpstart
from macho import ImageError
from session import Session


class JumpstartSessionTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.parent = Path(self.tmp.name)

    def tearDown(self):
        self.tmp.cleanup()

    def make_session(self, started, phase='awaiting-jumpstart', code=0, ecid='12345'):
        identifier = str(uuid.uuid4())
        folder = self.parent / (ecid + '-' + identifier)
        folder.mkdir(mode=0o700)
        image = folder / 'image'
        image.mkdir()
        hashes = {}
        for name in ('iBSS.restore.img3', 'iBSS.restore.patched', 'iBEC.jumpstart.img3'):
            content = (identifier + name).encode()
            (image / name).write_bytes(content)
            hashes[name] = hashlib.sha256(content).hexdigest()
        record = image / 'preparation.json'
        record.write_text(json.dumps(dict(boot_artifacts=hashes,
            jumpstart_ibec_sha256=hashes['iBEC.jumpstart.img3'])))
        payload = identifier.encode()
        (folder / 'payload_jumpstart').write_bytes(payload)
        data = dict(schema=1, session=identifier, ecid=ecid, product='iPhone5,4', board='n49ap',
            version='10.3.4', build='14G61', phase=phase, restorer_exit_code=code,
            history=[dict(to='restore-running', time=started)] if started else [],
            preparation=str(record), preparation_sha256=hashlib.sha256(record.read_bytes()).hexdigest(),
            assets_sha256={'payload_jumpstart': hashlib.sha256(payload).hexdigest()})
        (folder / 'session.json').write_text(json.dumps(data))
        return Session(folder)

    def test_selects_latest_completed_physical_restore_not_prepared_image(self):
        self.make_session(10)
        current = self.make_session(20)
        self.make_session(0, phase='image-ready')
        self.assertEqual([s.directory for s in jumpstart.candidates(self.parent)], [current.directory])

    def test_later_failed_or_in_progress_restore_blocks_older_success(self):
        for phase, code in (('restore-failed', 1), ('restore-running', None)):
            with self.subTest(phase=phase):
                self.make_session(10)
                self.make_session(20, phase=phase, code=code)
                self.assertEqual(jumpstart.candidates(self.parent), [])

    def test_installer_already_started_is_not_a_dfu_retry_candidate(self):
        self.make_session(10)
        self.make_session(20, phase='installing')
        self.assertEqual(jumpstart.candidates(self.parent), [])

    def test_filters_connected_ecid_and_lists_all_when_identity_unavailable(self):
        first = self.make_session(10)
        second = self.make_session(20, ecid='67890')
        self.assertEqual([s.directory for s in jumpstart.candidates(self.parent, '12345')], [first.directory])
        self.assertEqual([s.directory for s in jumpstart.candidates(self.parent)], [second.directory, first.directory])
        self.assertEqual(jumpstart.candidates(self.parent, '99999'), [])

    def test_changed_boot_files_block_retry_without_falling_back(self):
        self.make_session(10)
        current = self.make_session(20)
        (current.directory / 'image/iBEC.jumpstart.img3').write_bytes(b'changed')
        self.assertEqual(jumpstart.candidates(self.parent), [])
        with self.assertRaisesRegex(ImageError, 'checksum mismatch'):
            jumpstart.require_pending_restore(current)

    def test_no_physical_restore_or_failure_never_passes_direct_validation(self):
        for started, code in ((0, 0), (20, 1), (20, None)):
            with self.subTest(started=started, code=code):
                with self.assertRaises(ImageError):
                    jumpstart.require_pending_restore(self.make_session(started, code=code))


class JumpstartMenuTests(unittest.TestCase):
    run_shell = bridge.RestoreBridgeTests.run_shell

    def test_allinone_menu_does_not_offer_old_jumpstart_route(self):
        for device_mode in ('DFU', 'none'):
            result = self.run_shell(r'''
mode=
device_mode=DEVICE_MODE
device_ecid=
menu_print_info() { :; }
ios10_has_sessions() { return 0; }
select_option() {
    printf 'OPTION:%s\n' "$@"
    exit 0
}
menu_main
'''.replace('DEVICE_MODE', device_mode), extra_functions=('menu_main',))
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertNotIn('Jumpstart iOS 10 Untethered Jailbreak', result.stdout)
            self.assertNotIn('Resume iOS 10 Installation', result.stdout)

    def test_existing_dfu_is_accepted_without_forcing_exit(self):
        result = self.run_shell(r'''
device_mode=DFU
device_pwnd=stale
device_srtg=stale
ios10_session() { :; }
device_dfuhelper() { echo "GUIDE:$1"; device_mode=DFU; }
ios10_verify_recovery() { echo IDENTITY_OK; }
device_enter_mode() { echo "PWN:$1:$device_pwnd:$device_srtg"; }
ios10_enter_pwned_ibss
''')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('GUIDE:DFUreal', result.stdout)
        self.assertIn('PWN:pwnDFU::', result.stdout)
        self.assertNotIn('fresh DFU', result.stdout)
        self.assertNotIn('leaves DFU', result.stdout)

    def test_retry_still_checks_device_identity_before_exploiting(self):
        result = self.run_shell(r'''
device_dfuhelper() { :; }
ios10_session() { :; }
ios10_verify_recovery() { echo WRONG_PHONE; return 1; }
device_enter_mode() { echo UNEXPECTED_PWN; }
ios10_enter_pwned_ibss
''')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('WRONG_PHONE', result.stdout)
        self.assertNotIn('UNEXPECTED', result.stdout)

    def test_ibss_failure_hints_apply_only_to_jumpstart(self):
        for context in ('', '1'):
            result = self.run_shell(r'''
ios10_jumpstart_active=CONTEXT
ios10_ibss_dir="$ios10_session_dir/image"
mkdir "$ios10_ibss_dir"
printf packed > "$ios10_ibss_dir/iBSS.restore.img3"
printf raw > "$ios10_ibss_dir/iBSS.restore.patched"
ios10_session() { :; }
device_pwnd=ipwnder
fake_primepwn() { return 11; }
primepwn=fake_primepwn
device_send_unpacked_ibss
'''.replace('CONTEXT', context), extra_functions=('device_send_unpacked_ibss',))
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('Failed to send iBSS', result.stdout)
            self.assertEqual('Main Menu -> Jumpstart iOS 10 Untethered Jailbreak' in result.stdout, context == '1')
            self.assertEqual('restore has completed' in result.stdout, context == '1')

    def test_saved_retry_uses_normal_boot_and_capture_cleanup_without_restore(self):
        result = self.run_shell(r'''
ios10_host_init() { ios10_python=fake_python; }
fake_python() { printf 'iPhone5,4\tn49ap\t10.3.4\t14G61\t12345\n'; }
ios10_start_capture() { echo CAPTURE_START; }
ios10_stop_capture() { echo CAPTURE_STOP; }
ios10_jumpstart() {
    echo "BOOT:$1:$device_ecid:$device_model"
    exit 19
}
restore_idevicerestore() { echo UNEXPECTED_RESTORE; }
ios10_prepare_session() { echo UNEXPECTED_PREPARE; }
ios10_jumpstart_saved_session "$ios10_session_dir"
result=$?
echo "RETURNED_TO_MENU:$result:$mode"
exit "$result"
''')
        self.assertEqual(result.returncode, 19, result.stderr)
        self.assertIn('BOOT::12345:n49', result.stdout)
        self.assertIn('CAPTURE_STOP', result.stdout)
        self.assertIn('RETURNED_TO_MENU:19:downgrade', result.stdout)
        self.assertNotIn('UNEXPECTED', result.stdout)

    def test_no_eligible_session_warns_without_device_activity(self):
        result = self.run_shell(r'''
ios10_host_init() { ios10_python=fake_python; }
fake_python() { return 0; }
ios10_jumpstart_saved_session() { echo UNEXPECTED_BOOT; }
ios10_jumpstart_menu
''')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('second-stage attempt to enter pwnDFU failed', result.stdout)
        self.assertIn('cannot be used after a failed restore', result.stdout)
        self.assertNotIn('UNEXPECTED', result.stdout)


if __name__ == '__main__':
    unittest.main()
