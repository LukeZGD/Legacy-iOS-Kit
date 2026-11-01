#!/usr/bin/env python3
"""Host-side journal and installer continuation for a single restore.

This module does not erase devices or perform DFU exploitation. restore.sh owns
those steps and supplies their real result. Only an explicitly invoked continue
command opens the temporary USB SSH connection.
"""

import argparse
import contextlib
import io
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import socket
import subprocess
import tarfile
import time
import zipfile

from macho import ImageError
from prepare import BOARDS, IMAGE_RECIPE, archive_name, digest, validate_target, write_json

HERE = Path(__file__).resolve().parent
TRANSITIONS = {
    "staged": {"image-ready"},
    "image-ready": {"restore-running"},
    "restore-running": {"restore-failed", "awaiting-jumpstart", "restore-complete-boot-unverified"},
    "awaiting-jumpstart": {"installing"},
    "installing": {"awaiting-coldboot"},
    "awaiting-coldboot": {"coldboot-verified"},
    "coldboot-verified": {"cleanup-started"},
    "cleanup-started": {"complete"},
}


class ConnectionTimeout(ImageError):
    pass


def image_fingerprint(path):
    stat = Path(path).stat()
    return {name: getattr(stat, 'st_' + name) for name in ('dev', 'ino', 'size', 'mtime_ns', 'ctime_ns')}


def verify_image_checksum(path, expected, receipt=None):
    """Reuse a checksum only while its file identity and timestamps match."""
    before = image_fingerprint(path)
    if receipt == dict(before, sha256=expected):
        return receipt
    if digest(path, label='Verifying IPSW before restore') != expected:
        raise ImageError('Prepared IPSW checksum mismatch')
    if image_fingerprint(path) != before:
        raise ImageError('Prepared IPSW changed during verification')
    return dict(before, sha256=expected)


class Session:
    def __init__(self, directory):
        self.directory = Path(directory).resolve()
        self.path = self.directory / "session.json"
        self.data = json.loads(self.path.read_text())
        if (self.data.get("schema") != 1 or BOARDS.get(self.data.get("product")) != self.data.get("board")
                or not re.fullmatch(r"[a-f0-9-]{36}", self.data.get("session", ""))):
            raise ImageError("Invalid installer session metadata")
        if self.directory.stat().st_mode & 0o077:
            raise ImageError("Installer session directory must be private (mode 700)")
        validate_target(*(self.data.get(key) for key in ("product", "board", "version", "build")))

    def save(self):
        write_json(self.path, self.data)

    def transition(self, phase, **fields):
        old = self.data["phase"]
        if phase not in TRANSITIONS.get(old, set()):
            raise ImageError(f"Cannot continue session from {old} to {phase}")
        self.data.setdefault("history", []).append({"from": old, "to": phase, "time": int(time.time())})
        self.data.update(fields, phase=phase)
        self.save()

    def register_image(self, preparation):
        preparation = Path(preparation).resolve()
        image = json.loads(preparation.read_text())
        for key in ("product", "board", "version", "build", "stage_sha256"):
            if image.get(key) != self.data.get(key):
                raise ImageError("Prepared image does not match this session: " + key)
        if image.get("phase") != "image-prepared":
            raise ImageError("Image preparation did not complete")
        if digest(self.directory / "stage.tar") != self.data["stage_sha256"]:
            raise ImageError("Staging archive changed after preparation")
        receipt = verify_image_checksum(image['output'], image['output_sha256'])
        self.transition("image-ready", preparation=str(preparation), preparation_sha256=digest(preparation),
                        image=image["output"], image_sha256=image["output_sha256"], image_verification=receipt)

    def verify_image(self):
        if digest(self.data["preparation"]) != self.data["preparation_sha256"]:
            raise ImageError("Image preparation record changed")
        receipt = verify_image_checksum(self.data['image'], self.data['image_sha256'],
                                        self.data.get('image_verification'))
        if digest(self.directory / "stage.tar") != self.data["stage_sha256"]:
            raise ImageError("Staging archive checksum mismatch")
        if receipt != self.data.get('image_verification'):
            self.data['image_verification'] = receipt
            self.save()

    def check_space(self, workdir):
        """idevicerestore extracts OS into its cwd, even for a reused IPSW."""
        directory = Path(workdir).resolve(strict=True)
        record = Path(self.data['preparation'])
        if digest(record) != self.data['preparation_sha256']:
            raise ImageError('Image preparation record changed')
        info = json.loads(record.read_text())
        with zipfile.ZipFile(self.data['image']) as archive:
            filesystem_size = archive.getinfo(info['components']['OS']['path']).file_size
        margin = 512 * 1024**2
        required = filesystem_size + margin
        free = shutil.disk_usage(directory).free
        report = dict(workdir=str(directory), filesystem_bytes=filesystem_size,
                      margin_bytes=margin, required_bytes=required, free_bytes=free)
        self.data['space_check'] = report
        self.save()
        details = f'{required / 1024**3:.2f} GiB needed; {free / 1024**3:.2f} GiB available in {directory}'
        if free < required:
            raise ImageError('Not enough free space for restore extraction: ' + details)
        print('Restore disk space: ' + details, flush=True)
        return report

    def bind_normal_identity(self, raw):
        value = plistlib.loads(raw)
        if (value.get("ProductType") != self.data["product"]
                or value.get("HardwareModel", "").lower() != self.data["board"]
                or str(value.get("UniqueChipID")) != self.data["ecid"]):
            raise ImageError("Connected normal-mode device does not match this session")
        if not re.fullmatch(r"[0-9a-fA-F]{40}", value.get("UniqueDeviceID", "")):
            raise ImageError("Device did not supply a valid USB identifier")
        self.data.update(udid=value["UniqueDeviceID"], source_version=value.get("ProductVersion"),
                         source_build=value.get("BuildVersion"))
        self.save()

    def verify_boot_artifacts(self):
        record = Path(self.data["preparation"])
        if digest(record) != self.data["preparation_sha256"]:
            raise ImageError("Image preparation record changed")
        info = json.loads(record.read_text())
        names=("iBSS.restore.img3", "iBSS.restore.patched")
        if self.data.get('installer') != 'restore-allinone':names+=("iBEC.jumpstart.img3",)
        for name in names:
            if digest(record.parent / name) != info.get("boot_artifacts", {}).get(name):
                raise ImageError("Boot artifact checksum mismatch: " + name)
        if self.data.get('installer') == 'restore-allinone':
            if info.get('installer')!='restore-allinone' or info.get('recipe')!=IMAGE_RECIPE:
                raise ImageError('Expected an all-in-one restore image')
            return
        if digest(record.parent / "iBEC.jumpstart.img3") != info["jumpstart_ibec_sha256"]:
            raise ImageError("Jump-start iBEC checksum mismatch")
        if digest(self.directory / "payload_jumpstart") != self.data["assets_sha256"]["payload_jumpstart"]:
            raise ImageError("Jump-start payload checksum mismatch")

    def restore_result(self, code):
        success='restore-complete-boot-unverified' if self.data.get('installer')=='restore-allinone' else 'awaiting-jumpstart'
        self.transition(success if code == 0 else "restore-failed", restorer_exit_code=code)

    def verify_recovery_identity(self, text):
        values = {}
        for line in text.splitlines():
            if ":" in line:
                key, value = line.split(":", 1)
                values[key.strip()] = value.strip()
        try:
            # irecovery ECID is printed as 0x-prefixed hexadecimal.
            ecid = int(values["ECID"], 16 if values["ECID"].startswith("0x") else 10)
        except (KeyError, ValueError):
            raise ImageError("Recovery device did not report a valid ECID")
        if (ecid != int(self.data["ecid"]) or values.get("PRODUCT") != self.data["product"]
                or values.get("MODEL", "").lower() != self.data["board"]):
            raise ImageError("Connected recovery device does not match this restore session")
        return values


def parse_info(raw, session):
    text = raw.decode("utf-8")
    values = {}
    for line in text.splitlines():
        if "=" not in line:
            raise ImageError("Malformed installer identity response")
        key, value = line.split("=", 1)
        if key in values:
            raise ImageError("Duplicate installer identity field")
        values[key] = value
    for key in ("session", "product", "board", "version", "build", "ecid"):
        if values.get(key) != session.data[key]:
            raise ImageError("Booted installer identity mismatch: " + key)
    if values.get("uid") != "0" or not values.get("boot") or "bootargs" not in values:
        raise ImageError("Installer did not demonstrate root access and boot identity")
    return values


def springboard_settings(original):
    if len(original) > 2 * 1024**2:
        raise ImageError("Unexpectedly large SpringBoard settings file")
    try:
        value = plistlib.loads(original) if original else {}
    except Exception as exc:
        raise ImageError("Existing SpringBoard settings could not be parsed") from exc
    if not isinstance(value, dict):
        raise ImageError("SpringBoard settings are not a dictionary")
    value["SBShowNonDefaultSystemApps"] = True
    return plistlib.dumps(value, fmt=plistlib.FMT_BINARY if original.startswith(b"bplist") else plistlib.FMT_XML)


def ssh_rsa_options(executable):
    result = subprocess.run([str(executable), "-V"], stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, timeout=10)
    match = re.search(rb"OpenSSH_(\d+)\.(\d+)", result.stdout)
    if result.returncode != 0 or not match:
        raise ImageError("Could not identify the host OpenSSH client")
    version = tuple(map(int, match.groups()))
    # The temporary server offers one pinned RSA key. Exact selection works on
    # macOS 10.11's older SSH, which cannot parse all modern '+' options.
    options = ["-o", "HostKeyAlgorithms=ssh-rsa"]
    if version >= (8, 5):
        options += ["-o", "PubkeyAcceptedAlgorithms=+ssh-rsa"]
    return options


class SSH:
    def __init__(self, session, port, executable="ssh"):
        self.session, self.port = session, port
        self.executable = str(executable)
        self.rsa_options = ssh_rsa_options(executable)

    def argv(self, operation):
        if not re.fullmatch(r"[a-z-]+", operation):
            raise ImageError("Invalid installer operation")
        return [self.executable, "-F", os.devnull, "-T", "-p", str(self.port),
                "-i", str(self.session.directory / "client_rsa"),
                "-o", "BatchMode=yes", "-o", "IdentitiesOnly=yes", "-o", "StrictHostKeyChecking=yes",
                "-o", "UserKnownHostsFile=" + str(self.session.directory / "known_hosts"),
                "-o", "GlobalKnownHostsFile=" + os.devnull,
                "-o", "HostKeyAlias=lik-ios10-" + self.session.data["session"],
                *self.rsa_options,
                "-o", "ConnectTimeout=5", "-o", "ConnectionAttempts=1",
                "-o", "ServerAliveInterval=10", "-o", "ServerAliveCountMax=3",
                "root@127.0.0.1", operation]

    def run(self, operation, data=None, timeout=120, tolerate_disconnect=False):
        result = subprocess.run(self.argv(operation), input=data, stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE, timeout=timeout)
        if result.returncode != 0:
            if tolerate_disconnect and result.returncode == 255:
                return result.stdout
            error = result.stderr.decode(errors="replace").strip()
            raise ConnectionError(f"{operation} failed ({result.returncode}): {error}")
        return result.stdout

    def info(self):
        return parse_info(self.run("info"), self.session)


@contextlib.contextmanager
def usb_proxy(executable, session, udid=None, ssh_executable="ssh"):
    # Reserve a currently free localhost port; verify that iproxy stays running
    # after binding. Device selection is additionally protected by unique keys.
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        port = sock.getsockname()[1]
    args = [str(executable), "-l", "-s", "127.0.0.1"]
    if udid:
        args += ["-u", udid]
    args += [str(port) + ":44"]
    with (session.directory / "iproxy.log").open("ab") as log:
        proc = subprocess.Popen(args, stdout=log, stderr=log)
        try:
            time.sleep(0.5)
            if proc.poll() is not None:
                raise ImageError("USB proxy could not start; see iproxy.log")
            yield SSH(session, port, ssh_executable)
        finally:
            if proc.poll() is None:
                proc.terminate()
                try:
                    proc.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    proc.kill()
                    proc.wait()


def wait_info(ssh, timeout=240):
    deadline, error = time.monotonic() + timeout, "Device not connected"
    while time.monotonic() < deadline:
        try:
            return ssh.info()
        except (ConnectionError, subprocess.TimeoutExpired) as exc:
            error = str(exc)
            if any(s in error.lower() for s in ("host key verification failed", "permission denied",
                                                "remote host identification has changed")):
                raise ImageError(error)
            time.sleep(3)
    raise ConnectionTimeout("Installer connection timed out; session is preserved. " + error)


def wait_phase(ssh, expected, allowed_running, timeout=900):
    deadline = time.monotonic() + timeout
    last = None
    while time.monotonic() < deadline:
        info = ssh.info()
        phase = info.get("phase")
        if phase != last:
            print("Device installer: " + str(phase), flush=True)
            last = phase
        if phase == expected:
            return info
        if phase not in allowed_running:
            raise ImageError("Installer stopped in phase " + str(phase) + "; preserve the logs before recovery")
        time.sleep(3)
    raise ImageError("Installer has not completed; its job may still be running. Do not restart or run Socket.")


def tar_members(raw):
    result = {}
    with tarfile.open(fileobj=io.BytesIO(raw)) as tar:
        for member in tar:
            name = archive_name(member.name).rstrip("/")
            if name in result or name.startswith("/") or ".." in Path(name).parts:
                raise ImageError("Invalid capture archive path")
            result[name] = (member, tar.extractfile(member).read() if member.isfile() else None)
    return result


def verify_captures(before, after):
    """Read archives in memory; never extract device paths onto the host."""
    old, new = tar_members(before), tar_members(after)

    def regular(table, name):
        if name not in table or not table[name][0].isfile() or not table[name][1]:
            raise ImageError("Capture missing regular file: " + name)
        return table[name][1]

    for name in ("racoon.conf", "backboardd", "wifiFirmwareLoaderLegacy", "disabled.plist"):
        source = {"racoon.conf": "etc/racoon/racoon.conf", "disabled.plist": "var/db/com.apple.xpc.launchd/disabled.plist"}.get(
            name, "usr/libexec/" + name)
        if regular(old, source) != regular(new, "var/root/procyon/backup/" + name):
            raise ImageError("Procyon did not preserve its stock backup: " + name)
    loader = new.get("usr/libexec/wifiFirmwareLoaderLegacy", (None,))[0]
    if not loader or not loader.issym() or loader.linkname != "/usr/sbin/racoon":
        raise ImageError("Captured Wi-Fi trigger is incorrect")
    for name, expected in (("var/db/com.apple.xpc.launchd/disabled.plist", "procyon-disabled.plist"),
                            ("var/lib/dpkg/info/com.staturnz.procyon.postinst", "procyon-postinst")):
        if regular(new, name) != (HERE / "assets" / expected).read_bytes():
            raise ImageError("Captured Procyon configuration differs from its bundled original: " + name)
    regular(new, "etc/racoon/stage2")
    regular(new, "var/root/procyon/stage3.bin")
    if not any(n.startswith("var/root/procyon/stage1/part") and m.isfile() and b for n, (m, b) in new.items()):
        raise ImageError("Captured stage 1 is missing")


def save_logs(ssh, session):
    for name in ("bootstrap", "untether"):
        try:
            (session.directory / (name + ".log")).write_bytes(ssh.run(name + "-log"))
        except Exception:
            pass  # Do not hide the original installation/connection error.


def continue_install(session, ssh):
    phase = session.data["phase"]
    if phase not in ("awaiting-jumpstart", "installing", "awaiting-coldboot"):
        raise ImageError("Session cannot continue from " + phase)
    info = wait_info(ssh)
    if phase == "awaiting-jumpstart":
        if "lik_ios10_jumpstart=1" not in info["bootargs"].split():
            raise ImageError("A temporary DFU jump-start boot is required")
        session.transition("installing", jumpstart_boot=info["boot"])
    elif phase == "awaiting-coldboot" and info["boot"] == session.data["pre_cold_boot"]:
        # The host can stop after journaling this phase but before its reboot
        # request reaches the phone. Retry only that already-armed reboot.
        if (info.get("phase") != "untether-installed"
                or "lik_ios10_jumpstart=1" not in info["bootargs"].split()):
            raise ImageError("The pending cold boot no longer matches the completed installation")
        ssh.run("reboot", tolerate_disconnect=True)
    if session.data["phase"] == "installing":
        if "lik_ios10_jumpstart=1" not in info["bootargs"].split():
            raise ImageError("Installation was interrupted by a different boot; inspect the saved state")
        try:
            if info["phase"] == "new":
                ssh.run("start-bootstrap")
                info = wait_phase(ssh, "needs-settings", {"new", "bootstrap-running"})
            elif info["phase"] == "bootstrap-running":
                info = wait_phase(ssh, "needs-settings", {"bootstrap-running"})
            if info["phase"] == "needs-settings":
                original = ssh.run("get-settings")
                (session.directory / "springboard.original.plist").write_bytes(original)
                settings = springboard_settings(original)
                ssh.run("put-settings", settings)
                if ssh.run("get-staged-settings") != settings:
                    raise ImageError("SpringBoard settings upload verification failed")
                ssh.run("apply-settings")
                info = ssh.info()
            if info["phase"] == "settings-ready":
                ssh.run("start-untether")
                info = wait_phase(ssh, "untether-installed", {"settings-ready", "untether-running"})
            elif info["phase"] == "untether-running":
                info = wait_phase(ssh, "untether-installed", {"untether-running"})
            if info["phase"] != "untether-installed":
                raise ImageError("Cannot resume installer phase " + info["phase"])
            before, after = ssh.run("before-capture"), ssh.run("after-capture")
            (session.directory / "before.tar").write_bytes(before)
            (session.directory / "after.tar").write_bytes(after)
            verify_captures(before, after)
            save_logs(ssh, session)
            ssh.run("arm-cold-boot")
            session.transition("awaiting-coldboot", pre_cold_boot=info["boot"])
            print("Untether installed and persistent setup verified. Testing an ordinary reboot.", flush=True)
            ssh.run("reboot", tolerate_disconnect=True)
        finally:
            if session.data["phase"] == "installing":
                save_logs(ssh, session)
    deadline = time.monotonic() + 300
    while time.monotonic() < deadline:
        try:
            info = wait_info(ssh, timeout=min(30, max(1, deadline - time.monotonic())))
        except ConnectionTimeout:
            continue
        if info["boot"] != session.data["pre_cold_boot"]:
            if "lik_ios10_jumpstart=1" in info["bootargs"].split():
                raise ImageError("The new boot still uses the temporary payload; it is not an untether test")
            proof = ssh.run("cold-boot-proof")
            if re.search(rb"(?:/|\s)SpringBoard(?:\s|$)", proof):
                (session.directory / "cold-boot-proof.txt").write_bytes(proof)
                session.transition("coldboot-verified", cold_boot=info["boot"], hardware_tested=True)
                print("Ordinary boot reached SpringBoard with root access. Temporary transport remains for test diagnostics.", flush=True)
                return
        time.sleep(3)
    raise ImageError("Ordinary boot did not verify. Preserve this session; do not run Socket.")


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--directory", required=True)
    sub = p.add_subparsers(dest="action", required=True)
    sub.add_parser("status")
    reg = sub.add_parser("register-image")
    reg.add_argument("preparation")
    sub.add_parser("restore-start")
    space = sub.add_parser('check-space')
    space.add_argument('--workdir', required=True)
    sub.add_parser('verify-image')
    done = sub.add_parser("restore-result")
    done.add_argument("code", type=int)
    verify = sub.add_parser("verify-recovery")
    verify.add_argument("identity_file")
    normal = sub.add_parser("bind-normal")
    normal.add_argument("identity_file")
    sub.add_parser("verify-boot")
    observation = sub.add_parser("first-boot")
    observation.add_argument("observation", choices=["setup-screen", "apple-logo", "black-screen", "recovery", "other"])
    cont = sub.add_parser("continue")
    cont.add_argument("--iproxy", required=True)
    cont.add_argument("--udid")
    cont.add_argument("--ssh", default="ssh")
    a = p.parse_args()
    s = Session(a.directory)
    if a.action == "status":
        print(s.data["phase"])
    elif a.action == "register-image":
        s.register_image(a.preparation)
    elif a.action == "restore-start":
        s.verify_image()
        s.transition("restore-running")
    elif a.action == 'check-space':
        s.check_space(a.workdir)
    elif a.action == 'verify-image':
        s.verify_image()
    elif a.action == "restore-result":
        s.restore_result(a.code)
    elif a.action == "verify-recovery":
        s.verify_recovery_identity(Path(a.identity_file).read_text())
    elif a.action == "bind-normal":
        s.bind_normal_identity(Path(a.identity_file).read_bytes())
    elif a.action == "verify-boot":
        s.verify_boot_artifacts()
    elif a.action == "first-boot":
        if s.data["phase"] not in ("awaiting-jumpstart", "restore-complete-boot-unverified"):
            raise ImageError("No completed restore is awaiting a first-boot observation")
        s.data["automatic_first_boot_observation"] = a.observation
        s.save()
    elif a.action == "continue":
        with usb_proxy(a.iproxy, s, a.udid or s.data.get("udid"), a.ssh) as ssh:
            continue_install(s, ssh)


if __name__ == "__main__":
    try:
        main()
    except (ImageError, OSError, ValueError, KeyError, zipfile.BadZipFile, subprocess.TimeoutExpired) as exc:
        raise SystemExit(str(exc))
