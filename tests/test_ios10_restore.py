"""Exercise the restore bridge with fake USB, DFU and restorer operations."""
import os
import shlex
import subprocess
import tempfile
import unittest

from test_ios10_jailbreak_option import ROOT, function


class RestoreBridgeTests(unittest.TestCase):
    def run_shell(self, body, extra_functions=()):
        script = '\n'.join(function(n) for n in extra_functions)
        script += '\nsource ' + shlex.quote(str(ROOT / 'resources/ios10/restore.sh')) + '\n'
        script += r'''
log() { printf 'LOG:%s\n' "$*"; }
warn() { printf 'WARN:%s\n' "$*"; }
print() { printf '%s\n' "$*"; }
input() { printf 'INPUT:%s\n' "$*"; }
error() { printf 'ERROR:%s\n' "$*"; exit 1; }
sleep() { :; }
ios10_session_dir="$PWD/session"
mkdir "$ios10_session_dir"
ios10_python=python3
ios10_resources=RESOURCES
device_type=iPhone5,4
device_model=n49
device_proc=6
device_ecid=12345
device_target_vers=10.3.4
device_target_build=14G61
device_latest_vers=10.3.4
mode=downgrade
platform=macos
ipsw_path="$PWD/source"
printf fixture > "$ipsw_path.ipsw"
'''.replace('RESOURCES', shlex.quote(str(ROOT / 'resources/ios10'))) + body
        with tempfile.TemporaryDirectory() as directory:
            result = subprocess.run([os.environ.get('TEST_BASH', '/bin/bash'), '--noprofile', '--norc'],
                input=script, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                cwd=directory, timeout=10, env={'PATH': os.environ['PATH'], 'LC_ALL': 'C'})
        self.assertNotIn('command not found', result.stderr)
        return result

    def test_jumpstart_handoff_is_entirely_on_device(self):
        result = self.run_shell(r"""
select_option() { echo UNEXPECTED_MENU; }
ios10_session() { echo UNEXPECTED_SESSION; }
ios10_after_jumpstart
""")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('Install / Continue', result.stdout)
        self.assertIn('Complete Setup', result.stdout)
        self.assertIn('No further computer connection', result.stdout)
        self.assertIn('Export Logs', result.stdout)
        self.assertNotIn('UNEXPECTED', result.stdout)

    def test_jumpstart_upload_failure_never_prompts_or_installs(self):
        result = self.run_shell(r"""
ios10_enter_pwned_ibss() { :; }
fake_recovery() { return 7; }
irecovery=fake_recovery
ios10_after_jumpstart() { echo UNEXPECTED_MENU; }
ios10_jumpstart
""")
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn('UNEXPECTED_MENU', result.stdout)

    def test_running_jumpstart_resume_does_not_reboot(self):
        result = self.run_shell(r"""
ios10_host_init() { :; }
ios10_session() { echo awaiting-jumpstart; }
select_option() { return 0; }
ios10_after_jumpstart() { echo DIAGNOSTICS; }
ios10_jumpstart() { echo UNEXPECTED_DFU; }
ios10_resume_session "$ios10_session_dir"
""")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('DIAGNOSTICS', result.stdout)
        self.assertNotIn('UNEXPECTED_DFU', result.stdout)

    def test_success_records_restore_then_normal_boot_without_jumpstart(self):
        result = self.run_shell(r'''
ios10_enter_pwned_ibss() { echo DFU; }
ios10_session() { echo "SESSION:$*"; }
restore_idevicerestore() { echo RESTORE; return 0; }
ios10_observe_first_boot() { echo OBSERVE; }
ios10_jumpstart() { echo JUMPSTART; }
ios10_restore_session
''')
        self.assertEqual(result.returncode, 0, result.stderr)
        expected = ('SESSION:check-space --workdir', 'SESSION:verify-image', 'DFU', 'SESSION:restore-start', 'RESTORE', 'SESSION:restore-result 0',
                    'Restore completed.', 'The first boot may take longer')
        positions = [result.stdout.index(s) for s in expected]
        self.assertEqual(positions, sorted(positions))
        self.assertIn('No second DFU step or installer app is required', result.stdout)
        self.assertNotIn('JUMPSTART', result.stdout)
        self.assertNotIn('OBSERVE', result.stdout)

    def test_raw_serial_result_distinguishes_missing_evidence_and_failure(self):
        for marker, code in (('[LIK-AIO] INSTALLATION_COMPLETE:', 0),
                             ('unrelated serial output', 0),
                             ('[LIK-AIO] INSTALLATION_FAILED', 1)):
            with self.subTest(marker=marker):
                result = self.run_shell(r'''
ios10_enter_pwned_ibss() { :; }
ios10_session() { :; }
restore_idevicerestore() { return 0; }
ios10_observe_first_boot() { echo OBSERVE; }
ios10_serial_dir="$ios10_session_dir/capture"
mkdir "$ios10_serial_dir"
printf '[LIK-AIO] FINAL_MOUNTED_STAGE:\nMARKER\n' > "$ios10_serial_dir/serial.bin"
printf '[LIK-AIO] INSTALLATION_\n[timestamp] COMPLETE:' > "$ios10_serial_dir/serial.log"
ios10_restore_session
'''.replace('MARKER', marker))
                self.assertEqual(result.returncode, code, result.stderr)
                self.assertEqual('Restore completed.' in result.stdout, code == 0)
                self.assertNotIn('OBSERVE', result.stdout)
                if marker == 'unrelated serial output':
                    self.assertIn('does not prove installation failed', result.stdout)
                elif code == 0:
                    self.assertIn('verification: passed', result.stdout)

    def test_low_disk_space_stops_before_any_dfu_or_restore(self):
        result = self.run_shell(r'''
ios10_session() { echo "SESSION:$*"; [[ $1 != check-space ]]; }
ios10_enter_pwned_ibss() { echo UNEXPECTED_DFU; }
restore_idevicerestore() { echo UNEXPECTED_RESTORE; }
ios10_restore_session
''')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('SESSION:check-space --workdir', result.stdout)
        self.assertNotIn('UNEXPECTED', result.stdout)

    def test_failed_restore_retains_real_code_and_does_not_jumpstart(self):
        result = self.run_shell(r'''
ios10_enter_pwned_ibss() { echo DFU; }
ios10_session() { echo "SESSION:$*"; }
restore_idevicerestore() { echo RESTORE; return 27; }
ios10_observe_first_boot() { echo UNEXPECTED_OBSERVATION; }
ios10_jumpstart() { echo UNEXPECTED_BOOT; }
ios10_restore_session
''')
        self.assertEqual(result.returncode, 27, result.stderr)
        self.assertIn('SESSION:restore-result 27', result.stdout)
        self.assertNotIn('UNEXPECTED', result.stdout)
        self.assertNotIn('Restore completed.', result.stdout)

    def test_restore_log_keeps_error_output_and_real_failure_code(self):
        result = self.run_shell(r'''
ios10_enter_pwned_ibss() { :; }
ios10_session() { echo "SESSION:$*"; }
restore_idevicerestore() { echo RESTORER_STDOUT; echo RESTORER_ERROR >&2; return 27; }
ios10_jumpstart() { echo UNEXPECTED_BOOT; }
ios10_restore_session
result=$?
echo SAVED_LOG
cat "$ios10_session_dir/restore.log"
exit "$result"
''')
        self.assertEqual(result.returncode, 27, result.stderr)
        saved = result.stdout.split('SAVED_LOG\n')[1]
        self.assertIn('RESTORER_STDOUT', saved)
        self.assertIn('RESTORER_ERROR', saved)
        self.assertIn('SESSION:restore-result 27', result.stdout)
        self.assertNotIn('UNEXPECTED_BOOT', result.stdout)

    def test_upstream_restorer_wrapper_propagates_real_exit_code(self):
        for code in (0, 27):
            result = self.run_shell(r'''
printf ticket > ticket.shsh
shsh_path=ticket.shsh
ipsw_custom=fixture
fake_restorer() { return CODE; }
idevicerestore=fake_restorer
restore_idevicerestore ios10
'''.replace('CODE', str(code)), extra_functions=('restore_idevicerestore',))
            self.assertEqual(result.returncode, code, result.stderr)
            self.assertNotIn('Restoring done!', result.stdout)

    def test_log_write_failure_stops_continuation_without_falsifying_restore_result(self):
        result = self.run_shell(r'''
ios10_enter_pwned_ibss() { :; }
ios10_session() { echo "SESSION:$*"; }
restore_idevicerestore() { echo RESTORE_OUTPUT; return 0; }
tee() { cat; return 1; }
ios10_jumpstart() { echo UNEXPECTED_BOOT; }
ios10_restore_session
''')
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn('SESSION:restore-result 0', result.stdout)
        self.assertIn('log could not be saved', result.stdout)
        self.assertNotIn('UNEXPECTED_BOOT', result.stdout)

    def test_debug_logging_does_not_change_restore_cache_path(self):
        result = self.run_shell(r'''
printf ticket > ticket.shsh
shsh_path=ticket.shsh
ipsw_custom='image with spaces'
debug_mode=1
fake_restorer() { printf 'ARG:%s\n' "$@"; }
idevicerestore=fake_restorer
restore_idevicerestore ios10
''', extra_functions=('restore_idevicerestore',))
        self.assertEqual(result.returncode, 0, result.stderr)
        args = [line[4:] for line in result.stdout.splitlines() if line.startswith('ARG:')]
        self.assertEqual(args, ['-ey', '-d', '--cache-path', '.', 'image with spaces.ipsw'])

    def test_latest_does_not_load_saved_ticket_but_other_routes_still_do(self):
        for mode in ('ios10', 'first'):
            result = self.run_shell(r'''
printf OLD_TICKET > ticket.shsh
shsh_path=ticket.shsh
ipsw_custom=fixture
fake_restorer() { printf 'ARG:%s\n' "$@"; }
idevicerestore=fake_restorer
restore_idevicerestore MODE
if [[ -d shsh ]]; then echo CACHED_TICKET; fi
'''.replace('MODE', mode), extra_functions=('restore_idevicerestore',))
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual('CACHED_TICKET' in result.stdout, mode != 'ios10')
            self.assertEqual('ARG:-ewy' in result.stdout, mode != 'ios10')

    def test_memory_choice_can_enable_or_disable_fresh_build_ram(self):
        for answer, expected in ((1, '1'), (0, '0')):
            result = self.run_shell(r'''
select_yesno() { return ANSWER; }
ios10_memory_option
echo "MEMORY=$ipsw_memory"
'''.replace('ANSWER', str(answer)))
            self.assertIn('MEMORY=' + expected, result.stdout)

    def test_reuse_yes_skips_fresh_build_and_no_offers_memory_option(self):
        for answer in (0, 1):
            result = self.run_shell(r'''
mkdir runtime
cd runtime
ios10_resources=/fixture
ios10_tools=/tools
ios10_python=fake_python
fake_python() {
    case "$1" in
        -c) echo new-attempt;;
        /fixture/reuse.py)
            if [[ $2 == list ]]; then
                echo "$PWD/old-attempt"
            else
                echo REUSE_IMAGE
                mkdir -p "$ios10_session_dir/image"
            fi;;
        /fixture/stage.py) mkdir -p "$ios10_session_dir/image";;
        /fixture/prepare.py) echo "FRESH_BUILD:$*";;
    esac
}
select_yesno() {
    if [[ $1 == 'Reuse existing IPSW?' ]]; then return ANSWER; fi
    return 1
}
ios10_session() { echo "SESSION:$*"; }
ios10_verify_recovery() { :; }
ios10_prepare_session
'''.replace('ANSWER', str(answer)))
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual('REUSE_IMAGE' in result.stdout, answer == 1)
            self.assertEqual('FRESH_BUILD:' in result.stdout, answer == 0)
            self.assertEqual('INPUT:Memory Option' in result.stdout, answer == 0)
            if answer == 0:
                self.assertIn('--memory', result.stdout)

    def test_identity_mismatch_stops_before_exploiting_or_restoring(self):
        result = self.run_shell(r'''
ios10_session() { echo "SESSION:$*"; }
device_dfuhelper() { echo DFU_HELPER; }
ios10_verify_recovery() { echo WRONG_PHONE; return 1; }
device_enter_mode() { echo UNEXPECTED_PWN; }
ios10_enter_pwned_ibss
''')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('WRONG_PHONE', result.stdout)
        self.assertNotIn('UNEXPECTED', result.stdout)

    def test_success_finishes_without_a_screen_state_prompt(self):
        result = self.run_shell(r'''
ios10_enter_pwned_ibss() { :; }
ios10_session() { :; }
restore_idevicerestore() { return 0; }
select_option() { echo UNEXPECTED_PROMPT; return 1; }
ios10_restore_session
''')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn('UNEXPECTED_PROMPT', result.stdout)
        self.assertNotIn('Automatic first boot', result.stdout)

    def test_resume_does_not_repeat_erase_or_reboot_live_install(self):
        for phase in ('installing', 'awaiting-coldboot', 'restore-running', 'restore-failed'):
            result = self.run_shell(r'''
ios10_host_init() { :; }
ios10_session() { if [[ $1 == status ]]; then echo PHASE; else echo "SESSION:$*"; fi; }
ios10_jumpstart() { echo UNEXPECTED_REBOOT; }
restore_idevicerestore() { echo UNEXPECTED_ERASE; }
ios10_resume_session "$ios10_session_dir"
'''.replace('PHASE', phase))
            self.assertNotIn('UNEXPECTED', result.stdout)
            self.assertEqual(result.returncode == 0, phase in ('installing', 'awaiting-coldboot'))
            self.assertNotIn('SESSION:continue', result.stdout)

    def test_validated_model_preflight_keeps_other_restore_routes_guarded(self):
        for assignments, expected in (('', 0),
                                      ('device_type=iPhone5,1; device_model=n41', 0),
                                      ('device_type=iPhone5,2; device_model=n42', 0),
                                      ('device_type=iPhone5,3; device_model=n48', 0),
                                      ('device_type=iPad3,4; device_model=p101', 0),
                                      ('device_type=iPad3,5; device_model=p102', 0),
                                      ('device_type=iPad3,6; device_model=p103', 0),
                                      ('device_type=iPhone5,2', 1), ('device_model=n42', 1),
                                      ('device_type=iPad3,4; device_model=p102', 1),
                                      ('device_type=iPad3,1; device_model=j1', 1),
                                      ('device_target_other=1', 1), ('device_target_vers=10.3.3', 1),
                                      ('device_target_build=14G60', 1), ('device_skip_ibss=1', 1)):
            result = self.run_shell('ios10_host_init() { echo HOST_READY; }\n' + assignments + '\nios10_preflight\n')
            self.assertEqual(result.returncode, expected, result.stderr)
            self.assertEqual('HOST_READY' in result.stdout, expected == 0)

    def test_target_ibss_is_used_without_old_firmware_download(self):
        result = self.run_shell(r'''
ios10_ibss_dir="$ios10_session_dir/image"
mkdir "$ios10_ibss_dir"
printf packed-target > "$ios10_ibss_dir/iBSS.restore.img3"
printf raw-target > "$ios10_ibss_dir/iBSS.restore.patched"
ios10_session() { :; }
patch_ibss() { echo UNEXPECTED_DOWNLOAD; exit 99; }
fake_irecovery() {
    if [[ $1 == -f ]]; then cat "$2"; echo; else echo 'MODE: DFU'; fi
}
fake_gaster() { :; }
gaster=fake_gaster
irecovery=fake_irecovery
device_send_unpacked_ibss
''', extra_functions=('device_send_unpacked_ibss',))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('packed-target', result.stdout)
        self.assertNotIn('UNEXPECTED_DOWNLOAD', result.stdout)


if __name__ == '__main__':
    unittest.main()
