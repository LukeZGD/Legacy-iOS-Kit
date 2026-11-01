"""Exercise real restore.sh menu functions with device operations replaced.

Run with: python3 -m unittest discover -s tests -v
The restore.sh entry point is never sourced or executed by these tests.
"""
import os
import re
import shlex
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / "restore.sh").read_text()
FUNCTIONS = (
    "print", "input", "log", "warn", "error",
    "ipsw_ios10_jailbreak_target", "ipsw_ios10_jailbreak_message",
    "ipsw_ios10_jailbreak_preview", "ipsw_jailbreak_preflight",
    "ipsw_preference_set", "restore_run", "menu_ipsw", "menu_ipsw_browse",
)


def function(name):
    match = re.search(r"^" + re.escape(name) + r"\(\) \{\n.*?^\}\n", SOURCE, re.M | re.S)
    if not match:
        raise AssertionError("Missing shell function: " + name)
    return match.group(0)


class JailbreakOptionTests(unittest.TestCase):
    def run_shell(self, body, **overrides):
        defaults = dict(
            device_type="iPhone5,2", device_proc="6", device_mode="Normal",
            device_proc_32bit="6", device_proc_checkm8="11", device_proc_unsupported="14",
            device_latest_vers="10.3.4", device_latest_build="14G61",
            device_target_vers="10.3.4", device_target_build="14G61",
            target_vers_maj="10", target_vers_min="3", mode="downgrade",
            platform="macos", platform_arch="arm64", device_use_bb="0",
            ipsw_path="fixture", ipsw_memory="1", answer="1",
            color_R="<red>", color_Y="<yellow>", color_G="<green>",
            color_B="<blue>", color_N="</color>",
            menu_choice="(*) Start Restore",
        )
        defaults.update(overrides)
        assignments = "\n".join(k + "=" + shlex.quote(str(v)) for k, v in defaults.items())
        stubs = r'''
select_yesno() { printf 'PROMPT:%s:default=%s\n' "$1" "$2"; return "$answer"; }
ipsw_custom_set() { :; }
ipsw_latest_set() { ipsw_latest_path=fixture-latest; }
ipsw_print_warnings() { :; }
menu_print_info() { :; }
pause() { :; }
restore_deviceprepare() { echo DEVICE_PREPARATION; }
ipsw_prepare() { echo IMAGE_PREPARATION; }
restore_prepare() { echo RESTORE; }
ios10_load_bridge() { :; }
ios10_preflight() { return 1; }
ios10_restore_run() { echo IOS10_RESTORE; }
select_option() {
    local i=0 item
    for item in "$@"; do
        printf 'OPTION:%s\n' "$item"
    done
    for item in "$@"; do
        if [[ $item == "$menu_choice" ]]; then return "$i"; fi
        ((i+=1))
    done
    echo 'Missing test menu selection' >&2
    exit 90
}
'''
        script = "\n".join(function(n) for n in FUNCTIONS) + assignments + "\n" + stubs + body
        with tempfile.TemporaryDirectory() as directory:
            result = subprocess.run(
                [os.environ.get("TEST_BASH", "/bin/bash"), "--noprofile", "--norc"],
                input=script, text=True, capture_output=True, cwd=directory,
                env={"PATH": os.environ["PATH"], "LC_ALL": "C"}, timeout=10,
            )
        self.assertNotIn("command not found", result.stderr)
        return result

    def test_latest_support_message_distinguishes_hardware_tested_model(self):
        for product in ('iPhone5,1','iPhone5,2','iPhone5,3','iPhone5,4','iPad3,4','iPad3,5','iPad3,6'):
            with self.subTest(product=product):
                result=self.run_shell('ipsw_ios10_jailbreak_message\n',device_type=product)
                self.assertEqual(result.returncode,0,result.stderr)
                self.assertNotIn('Selecting Y will stop',result.stdout)
                self.assertEqual('this model has not been tested on hardware' in result.stdout,product not in ('iPhone5,2','iPhone5,4','iPad3,4'))
        result=self.run_shell('ipsw_ios10_jailbreak_message\n',device_target_other='1')
        self.assertIn('Selecting Y will stop',result.stdout)

    def test_latest_prompt_for_all_a6_variants(self):
        for model, version in (
            ("iPhone5,1", "10.3.4"), ("iPhone5,2", "10.3.4"),
            ("iPhone5,3", "10.3.4"), ("iPhone5,4", "10.3.4"),
            ("iPad3,4", "10.3.4"), ("iPad3,5", "10.3.4"), ("iPad3,6", "10.3.4"),
        ):
            with self.subTest(model=model):
                result = self.run_shell(
                    'ipsw_preference_set\nprintf "SELECTED:%s:%s\\n" "$ipsw_jailbreak" "$ipsw_jailbreak_ios10"\n',
                    device_type=model, device_latest_vers=version, device_target_vers=version,
                )
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn("<yellow>[Input] Jailbreak Option</color>", result.stdout)
                self.assertIn("SELECTED:1:1", result.stdout)
                self.assertIn("without sideloading", result.stdout)
                self.assertNotIn("Cydia to be pre-installed", result.stdout)

    def test_shsh_prompt_including_latest(self):
        for version in ("10.0.1", "10.2.1", "10.3.3", "10.3.4"):
            with self.subTest(version=version):
                result = self.run_shell('ipsw_preference_set\n', device_target_other="1", device_target_vers=version, shsh_path="saved.shsh")
                self.assertIn("[Input] Jailbreak Option", result.stdout)
                self.assertIn("Socket's jailbreak assets, Zebra", result.stdout)

    def test_latest_preview_precedes_start_restore(self):
        result = self.run_shell('menu_ipsw "Latest iOS (10.3.4)"\n', mode="")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertLess(result.stdout.index("without sideloading"), result.stdout.index("OPTION:(*) Start Restore"))
        self.assertIn("without sideloading, a second DFU step", result.stdout)
        self.assertIn("OPTION:(*) Start Update", result.stdout)

    def test_shsh_preview_and_no_update_that_would_ignore_blob(self):
        result = self.run_shell('menu_ipsw "Other (Use SHSH Blobs)"\n', mode="", shsh_path="saved.shsh")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertLess(result.stdout.index("without sideloading"), result.stdout.index("OPTION:(*) Start Restore"))
        self.assertNotIn("OPTION:(*) Start Update", result.stdout)

    def test_shsh_preview_waits_for_ipsw_and_blob(self):
        for ipsw, blob in (("", "saved.shsh"), ("fixture", "")):
            with self.subTest(ipsw=ipsw, blob=blob):
                result = self.run_shell('ipsw_ios10_jailbreak_preview\n', device_target_other="1", ipsw_path=ipsw, shsh_path=blob)
                self.assertEqual(result.stdout, "")

    def test_unavailable_install_stops_before_any_device_action(self):
        for route, mode in (("", "downgrade"), ("1", "downgrade"), ("1", "custom-ipsw")):
            with self.subTest(route=route, mode=mode):
                result = self.run_shell('restore_run\n', device_target_other=route, mode=mode)
                self.assertEqual(result.returncode, 1)
                self.assertIn("preparation did not pass", result.stdout)
                for operation in ("DEVICE_PREPARATION", "IMAGE_PREPARATION", "\nRESTORE\n"):
                    self.assertNotIn(operation, result.stdout)

    def test_cli_flag_cannot_bypass_guard(self):
        result = self.run_shell('restore_run\n', ipsw_jailbreak="1")
        self.assertEqual(result.returncode, 1)
        self.assertNotIn("PROMPT:", result.stdout)
        self.assertNotIn("DEVICE_PREPARATION", result.stdout)

    def test_validated_ios10_request_uses_integrated_flow_instead_of_legacy_builder(self):
        result = self.run_shell('ios10_preflight() { return 0; }\nrestore_run\n', device_type="iPhone5,4")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("IOS10_RESTORE", result.stdout)
        self.assertNotIn("DEVICE_PREPARATION", result.stdout)
        self.assertNotIn("IMAGE_PREPARATION", result.stdout)

    def test_declining_preserves_normal_restore_on_both_routes(self):
        for route in ("", "1"):
            with self.subTest(route=route):
                result = self.run_shell('restore_run\nprintf "SELECTED:%s:%s\\n" "$ipsw_jailbreak" "$ipsw_jailbreak_ios10"\n', device_target_other=route, answer="0")
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn("DEVICE_PREPARATION\nIMAGE_PREPARATION\nRESTORE", result.stdout)
                self.assertIn("SELECTED::", result.stdout)

    def test_ipad_notice_is_version_specific(self):
        for model, version, expected in (("iPad3,4", "10.3.3", True), ("iPad3,5", "10.3.4", True), ("iPad3,4", "10.3.1", False), ("iPhone5,2", "10.3.4", False)):
            with self.subTest(model=model, version=version):
                result = self.run_shell('ipsw_preference_set\n', device_type=model, device_target_vers=version, device_target_other="1")
                self.assertEqual("about 7%" in result.stdout.lower(), expected)

    def test_other_boot_chains_and_64bit_do_not_get_new_option(self):
        for settings in (dict(device_target_tethered="1"), dict(device_target_powder="1"), dict(ipsw_isbeta="1"), dict(device_proc="7", device_type="iPhone6,1")):
            with self.subTest(settings=settings):
                result = self.run_shell('ipsw_preference_set\n', **settings)
                self.assertNotIn("Socket's jailbreak assets", result.stdout)

    def test_older_jailbreak_wording_and_execution_are_unchanged(self):
        result = self.run_shell('restore_run\n', device_target_vers="8.4.1", target_vers_maj="8", target_vers_min="4")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("jailbreak and Cydia to be pre-installed", result.stdout)
        self.assertIn("DEVICE_PREPARATION\nIMAGE_PREPARATION\nRESTORE", result.stdout)
        self.assertNotIn("Procyon", result.stdout)

    def browse_latest_fixture(self, **overrides):
        body = r'''
printf 'test IPSW placeholder' > 'fixture with spaces.ipsw'
printf '%s\n' "$fixture_product" > Restore.plist
ipsw_version_set() { :; }
ipsw_verify() { echo VERIFIED_IPSW; return "$verification_result"; }
ls() { return 0; }
fake_picker() { printf '%s/fixture with spaces.ipsw\n' "$PWD"; }
menu_zenity_check() { zenity=fake_picker; }
ipsw_path=
menu_ipsw_browse "Latest iOS (10.3.4)"
printf 'CHOSEN:%s\n' "${ipsw_path##*/}"
'''
        settings = dict(device_type="iPhone5,4", fixture_product="iPhone5,4", verification_result="0")
        settings.update(overrides)
        return self.run_shell(body, **settings)

    def test_latest_file_picker_accepts_1034_for_all_a6_variants(self):
        for model in ("iPhone5,1", "iPhone5,2", "iPhone5,3", "iPhone5,4", "iPad3,4", "iPad3,5", "iPad3,6"):
            with self.subTest(model=model):
                result = self.browse_latest_fixture(device_type=model, fixture_product=model)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn("VERIFIED_IPSW", result.stdout)
                self.assertIn("CHOSEN:fixture with spaces", result.stdout)
                self.assertNotIn("not supported as target version", result.stdout)

    def test_latest_file_picker_still_rejects_old_wrong_or_unverified_firmware(self):
        for settings in (dict(device_target_vers="10.3.3", device_target_build="14G60"),
                         dict(fixture_product="iPhone5,2"), dict(verification_result="1")):
            with self.subTest(settings=settings):
                result = self.browse_latest_fixture(**settings)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn("CHOSEN:\n", result.stdout)
                self.assertNotIn("CHOSEN:fixture", result.stdout)

    def test_latest_ipsw_can_be_selected_in_shsh_route(self):
        # Exercise the file picker and validation branch; no real IPSW, network
        # access or host home-directory search is needed.
        body = r'''
printf 'test IPSW placeholder' > fixture.ipsw
echo iPhone5,2 > Restore.plist
ipsw_version_set() { :; }
ipsw_verify() { echo VERIFIED_IPSW; return 0; }
ls() { echo fixture.ipsw; }
menu_choice=fixture.ipsw
ipsw_path=
menu_ipsw_browse "Other (Use SHSH Blobs)"
printf 'CHOSEN:%s\n' "$ipsw_path"
'''
        result = self.run_shell(body, device_target_other="1")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("VERIFIED_IPSW", result.stdout)
        self.assertIn("CHOSEN:fixture", result.stdout)
        self.assertNotIn('select the "Latest iOS" option instead', result.stdout)


if __name__ == "__main__":
    unittest.main()
