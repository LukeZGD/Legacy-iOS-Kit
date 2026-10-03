# SPDX-License-Identifier: GPL-3.0-or-later
"""Test cache/profile selection without opening USB or downloading firmware."""
from pathlib import Path
import re
import subprocess
import tempfile
import unittest
from build import patch_btserver, bluetooth_resources

REPO = Path(__file__).resolve().parents[4]
SCRIPT = (REPO / 'restore.sh').read_text()

def function(name):
    return re.search(r'^' + name + r'\(\) \{\n.*?^\}', SCRIPT, re.M | re.S).group()


def shell(body, cwd=None):
    return subprocess.run(['bash', '-c', body], cwd=cwd, capture_output=True, text=True)


class Integration(unittest.TestCase):
    def test_invalid_firmware_rejected(self):
        for func in [patch_btserver, bluetooth_resources]:
            with self.assertRaises(ValueError):
                func(bytes(32))

    def test_output_name_isolated(self):
        fn = function('ipsw_custom_set')
        common = 'device_type=iPod4,1; device_target_vers=7.1.2; device_target_build=11D257; '
        original = shell(fn + '\n' + common + 'ipsw_custom_set; echo "$ipsw_custom"')
        fixed = shell(fn + '\n' + common + 'touch4_hardware_kext=/donor; ipsw_custom_set; echo "$ipsw_custom"')
        self.assertEqual(original.stdout.strip(), '../iPod4,1_7.1.2_11D257_Custom')
        self.assertEqual(fixed.stdout.strip(), original.stdout.strip() + '-HardwareV1')

    def test_preflight_scope(self):
        fn = function('ipsw_touch4_hardware_check')
        common = fn + '\nerror() { exit 97; }; warn() { :; }; python3_init() { :; };\n'
        self.assertEqual(shell(common + 'ipsw_touch4_hardware_check').returncode, 0)
        for overrides in ['device_type=iPhone3,3', 'device_target_build=11A465',
                          'device_base_build=10A403', 'ipsw_jailbreak=0']:
            result = shell(common + 'touch4_hardware_kext=/donor; device_type=iPod4,1; '
                           'device_target_build=11D257; device_base_build=10B500; ipsw_jailbreak=1; '
                           + overrides + '; ipsw_touch4_hardware_check')
            self.assertEqual(result.returncode, 97)

    def test_menu_enables_complete_restore(self):
        fn = function('menu_ipsw_special')
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'work').mkdir()
            donor = root / 'saved/touch4-ios7/donors/AppleCS42L59Audio.kext'
            donor.mkdir(parents=True)
            for name in ['AppleCS42L59Audio', 'Info.plist']:
                (donor / name).write_bytes(b'test')
            script = fn + """
print() { echo "$*"; }; warn() { :; }; input() { :; }; pause() { :; };
menu_print_info() { :; }; ipsw_latest_set() { :; }; ipsw_print_warnings() { :; };
select_option() { selections=$((selections + 1)); if [[ $selections == 1 ]]; then return 4; else return 5; fi; };
device_type=iPod4,1; device_latest_vers=6.1.6; device_latest_build=10B500;
ipsw_path=target; ipsw_base_path=base;
menu_ipsw_special 7.1.2;
echo "RESULT: $mode $ipsw_jailbreak $touch4_hardware_kext"
"""
            result = shell(script, root / 'work')
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('repairs: ENABLED', result.stdout)
            self.assertIn('RESULT: downgrade 1 ' + str(donor.resolve()), result.stdout)

    def test_justboot_profiles(self):
        fn = function('device_justboot_specialios7')
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'work').mkdir()
            save = root / 'saved/touch4-ios7'
            cache = save / '11D257'
            (cache / 'hardware').mkdir(parents=True)
            (cache / 'kernelcache').write_bytes(b'original')
            (cache / 'hardware/kernelcache').write_bytes(b'patched')
            for profile, expected in [('', '../saved/touch4-ios7/11D257/kernelcache'),
                                      ('cs59-v1', '../saved/touch4-ios7/11D257/hardware/kernelcache')]:
                (save / 'test-device').write_text('device_target_build=11D257\ntouch4_hardware_profile=' + profile + '\n')
                script = fn + '''
error() { exit 97; }; log() { :; }; sleep() { :; };
device_enter_mode() { :; }; device_find_mode() { :; }; patch_ibss() { :; };
record() { printf '%s\n' "$*"; };
irecovery=record; device_ecid=test-device; device_type=iPod4,1;
device_justboot_specialios7
'''
                result = shell(script, root / 'work')
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn('-f ' + expected + '\n', result.stdout)
                self.assertIn('-f ../resources/patch/touch4-ios7/DeviceTree.n81ap.img3\n', result.stdout)
            (cache / 'hardware/kernelcache').unlink()
            result = shell(script, root / 'work')
            self.assertEqual(result.returncode, 97)
            self.assertEqual(result.stdout, '')


if __name__ == '__main__':
    unittest.main()
