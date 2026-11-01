#!/usr/bin/env python3
"""Prepare a per-restore installer archive and private host credentials offline.

This never contacts a phone. The archive is an input to prepare.py, not an
installation command. Client private keys must never be copied into an IPSW.
"""

import argparse
import hashlib
import io
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import tarfile
import uuid

from macho import ImageError, relocate_dylibs
from prepare import archive_name, digest, validate_stage, validate_runtime, validate_target, write_json

HERE = Path(__file__).resolve().parent
DEVICE = "/usr/local/share/lik-ios10"
DAEMON = "org.legacyioskit.ios10.transport"
KIT_ARCHIVES = {
    "openssh.tar.gz": "96d7ecd8b71cfafe3e722cebc5a635b0484544fa1d453cbda98c35a4f091b293",
    "openssl.tar.gz": "7b1c997fb9b320d7de401130e6fd37884807d5dcb6ceeca2b391c94b6a4e4d32",
}
LIBRARIES = ("libcrypto.0.9.8.dylib", "libssl.0.9.8.dylib", "libreadline.6.0.dylib",
             "libhistory.6.0.dylib", "libncurses.5.dylib")
BOOTSTRAP_TOOLS = ("bash", "tar", "cat", "mkdir", "mv", "cp", "rm", "ln", "sleep",
                   "sync", "chmod", "chown", "readlink", "dd")


def archive_file(archive, name):
    with tarfile.open(archive) as tar:
        matches = [m for m in tar if archive_name(m.name) == name]
        if len(matches) != 1 or not matches[0].isfile():
            raise ImageError("Missing/ambiguous regular archive member: " + name)
        return tar.extractfile(matches[0]).read()


def runtime_files(resources):
    """Relocate only private copies; retain all source archives byte-for-byte."""
    resources = Path(resources)
    for name, sha in KIT_ARCHIVES.items():
        if digest(resources / "jailbreak" / name) != sha:
            raise ImageError("Kit transport archive checksum mismatch: " + name)
    assets = resources / "ios10/assets"
    manifest = json.loads((assets / "manifest.json").read_text())
    for name, sha in manifest["sha256"].items():
        if Path(name).name != name or digest(assets / name) != sha:
            raise ImageError("Pinned asset checksum mismatch: " + name)
    bootstrap = assets / "bootstrap.tar"
    files = {name: archive_file(bootstrap, "bin/" + name) for name in BOOTSTRAP_TOOLS}
    for name, source in (("sysctl", "usr/sbin/sysctl"), ("sw_vers", "usr/bin/sw_vers"),
                         ("cmp", "usr/bin/cmp")):
        files[name] = archive_file(bootstrap, source)
    files["sshd"] = archive_file(resources / "jailbreak/openssh.tar.gz", "usr/sbin/sshd")
    for name in ("ssh", "ssh-keygen"):
        files[name] = archive_file(resources / "jailbreak/openssh.tar.gz", "usr/bin/" + name)
    ssl = resources / "jailbreak/openssl.tar.gz"
    files["openssl"] = archive_file(ssl, "usr/bin/openssl")
    for lib in LIBRARIES:
        files[lib] = archive_file(ssl if lib.startswith(("libcrypto", "libssl")) else bootstrap,
                                  "usr/lib/" + lib)
    mapping = {"/usr/lib/" + name: "/usr/lik/" + name for name in LIBRARIES}
    result, report = {}, {}
    for name, original in files.items():
        modified, changes = relocate_dylibs(original, mapping)
        result["usr/lik/" + name] = (modified, 0o755)
        report[name] = {"original_sha256": hashlib.sha256(original).hexdigest(),
                        "sha256": hashlib.sha256(modified).hexdigest(), "changes": changes}
    # These are the exact fat helpers Socket repairs and copies on first use.
    for name in ("tar", "launchctl", "bootstrap.tar", "zebra.deb", "procyon.deb",
                 "procyon-postinst", "procyon-disabled.plist"):
        result[DEVICE.lstrip("/") + "/" + name] = ((assets / name).read_bytes(),
                                                   0o755 if name in ("tar", "launchctl") else 0o644)
    # Prebuilt ARMv7 binaries run on the device; no host compiler/SDK is needed.
    metadata = json.loads((assets / "socket-system-build.json").read_text())
    with tarfile.open(assets / "socket-system.tar") as archive:
        seen = set()
        for member in archive:
            name = archive_name(member.name)
            if not member.isfile() or name in seen or name in result:
                raise ImageError("Invalid diagnostic archive entry")
            data = archive.extractfile(member).read()
            if metadata["files_sha256"].get(name) != hashlib.sha256(data).hexdigest():
                raise ImageError("Diagnostic file checksum mismatch: " + name)
            mode = 0o755 if name in ("Applications/LIKTools.app/LIKTools", DEVICE.lstrip("/") + "/diagnostic-helper") else 0o644
            if member.mode != mode or member.uid != 0 or member.gid != 0:
                raise ImageError("Invalid diagnostic file permissions")
            result[name] = (data, mode)
            seen.add(name)
        if seen != set(metadata["files_sha256"]):
            raise ImageError("Incomplete diagnostic archive")
    return result, report, manifest


def sshd_config(session="unconfigured"):
    # Compatible with Kit's OpenSSH 6.7. No password, network-interface listener,
    # user rc, shell escape or general remote shell. sshd's privilege-separation
    # account/directory are absent in stock iOS; this temporary server is USB-only.
    return (f"""Protocol 2
Port 44
AddressFamily inet
ListenAddress 127.0.0.1
HostKey {DEVICE}/host_rsa
AuthorizedKeysFile {DEVICE}/authorized_keys /var/root/lik-ios10/{session}/ssh-selftest.pub
PidFile /var/run/lik-ios10-sshd.pid
AllowUsers root
PermitRootLogin without-password
PubkeyAuthentication yes
PasswordAuthentication no
ChallengeResponseAuthentication no
PermitEmptyPasswords no
UsePAM no
UsePrivilegeSeparation no
UseDNS no
StrictModes yes
AllowAgentForwarding no
AllowTcpForwarding no
AllowStreamLocalForwarding no
PermitTunnel no
X11Forwarding no
PermitTTY no
PermitUserEnvironment no
PermitUserRC no
PrintMotd no
PrintLastLog no
LoginGraceTime 20
MaxAuthTries 3
MaxSessions 2
ForceCommand /usr/lik/bash {DEVICE}/transport.sh
""").encode()


def keygen(path, comment):
    subprocess.run(["ssh-keygen", "-q", "-t", "rsa", "-b", "3072", "-m", "PEM",
                    "-N", "", "-C", comment, "-f", str(path)], check=True)
    path.chmod(0o600)
    pub = path.with_suffix(".pub").read_text().split()
    if len(pub) < 2 or pub[0] != "ssh-rsa":
        raise ImageError("Unexpected generated key format")
    return " ".join(pub[:2])


def add_archive(path, files):
    """GNU tar headers match bundled hfsplus; no PAX metadata or host ownership."""
    parents = set()
    for name in files:
        parents.update(str(p) for p in Path(name).parents if str(p) != ".")
    with tarfile.open(**({"fileobj": path} if hasattr(path, "write") else {"name": path}), mode="w", format=tarfile.GNU_FORMAT) as tar:
        for name in sorted(parents, key=lambda n: (n.count("/"), n)):
            m = tarfile.TarInfo(name + "/")
            m.type, m.mode = tarfile.DIRTYPE, 0o755
            tar.addfile(m)
        for name, (data, mode) in sorted(files.items()):
            m = tarfile.TarInfo(name)
            m.mode = mode
            if name == "bin/sh":
                m.type, m.linkname = tarfile.SYMTYPE, data.decode()
                tar.addfile(m)
            else:
                m.size = len(data)
                tar.addfile(m, io.BytesIO(data))


def session_files(directory, info, files, public):
    session, product, board, version, build, ecid = (info[k] for k in
                                                   ('session', 'product', 'board', 'version', 'build', 'ecid'))
    prefix = DEVICE.lstrip("/") + "/"
    files[prefix + "host_rsa"] = ((directory / "host_rsa").read_bytes(), 0o600)
    files[prefix + "authorized_keys"] = (("no-agent-forwarding,no-port-forwarding,no-pty,no-user-rc,no-X11-forwarding "
                                            + public + "\n").encode(), 0o600)
    files[prefix + "sshd_config"] = (sshd_config(session), 0o600)
    files[prefix + "session.json"] = ((json.dumps(info, sort_keys=True) + "\n").encode(), 0o644)
    # Values are restricted above; scripts read this line-based format as data,
    # without source/eval. No credentials are embedded in it.
    files[prefix + "identity"] = (("\n".join((session, product, board, version, build, ecid)) + "\n").encode(), 0o644)
    for name in ("common.sh", "transport.sh", "install.sh", "local-install.sh"):
        files[prefix + name] = ((HERE / "device" / name).read_bytes(), 0o755)
    for phase in ("bootstrap", "untether"):
        plist = dict(Label="org.legacyioskit.ios10." + phase,
                     ProgramArguments=["/usr/lik/bash", DEVICE + "/install.sh", phase],
                     RunAtLoad=True, KeepAlive=False, UserName="root",
                     StandardOutPath="/var/root/lik-ios10/" + session + "/" + phase + ".log",
                     StandardErrorPath="/var/root/lik-ios10/" + session + "/" + phase + ".log")
        files[prefix + phase + ".plist"] = (plistlib.dumps(plist), 0o644)
    plist = dict(Label=DAEMON, ProgramArguments=["/usr/lik/sshd", "-D", "-e", "-f", DEVICE + "/sshd_config"],
                 # A stock cold boot can try this job before Procyon has
                 # patched code signing. Retry failed starts after that point.
                 # Installer jobs above deliberately remain one-shot jobs.
                 RunAtLoad=True, KeepAlive={"SuccessfulExit": False}, ThrottleInterval=15, UserName="root",
                 StandardOutPath="/var/log/lik-ios10-transport.log",
                 StandardErrorPath="/var/log/lik-ios10-transport.log")
    files["Library/LaunchDaemons/" + DAEMON + ".plist"] = (plistlib.dumps(plist), 0o644)
    files["bin/sh"] = (b"/usr/lik/bash", 0o755)
    # Native helper can restore the exact staged SSH runtime, with per-session
    # server/public keys. The client's private key remains on the host only.
    repair = {}
    repair_names = [name for name in files if name.startswith("usr/lik/")]
    repair_names += [prefix + name for name in ("sshd_config", "host_rsa", "authorized_keys", "launchctl", "transport.sh", "common.sh")]
    repair_names.append("Library/LaunchDaemons/" + DAEMON + ".plist")
    for index, name in enumerate(sorted(repair_names)):
        data, mode = files[name]
        source = prefix + "ssh-repair/" + str(index)
        files[source] = (data, 0o600)
        repair["/" + name] = dict(source="/" + source, sha256=hashlib.sha256(data).hexdigest(), mode=mode)
    files[prefix + "ssh-repair.plist"] = (plistlib.dumps(repair), 0o600)
    # Device-side hashes cover scripts, private runtime and the unmodified
    # bootstrap/package bytes. Session credentials are never printed in logs.
    sums = "".join(hashlib.sha256(data).hexdigest() + "  /" + name + "\n"
                   for name, (data, _) in sorted(files.items()) if name != "bin/sh")
    files[prefix + "SHA256SUMS"] = (sums.encode(), 0o644)
    return files


def restore_files(directory, info, files, public):
    # Restore only the system app. All privileged installation resources stay
    # inside its bundle until the user runs Install / Continue after jump-start.
    app_prefix = "Applications/LIKTools.app/"
    app_files = {name: value for name, value in files.items() if name.startswith(app_prefix)}
    runtime = {name: value for name, value in files.items() if not name.startswith(app_prefix)}
    runtime = session_files(directory, info, runtime, public)
    runtime_archive = io.BytesIO()
    add_archive(runtime_archive, runtime)
    runtime_data = runtime_archive.getvalue()
    app_files[app_prefix + "runtime.tar"] = (runtime_data, 0o644)
    app_files[app_prefix + "runtime.sha256"] = ((hashlib.sha256(runtime_data).hexdigest() + "\n").encode(), 0o644)
    app_files[app_prefix + "identity"] = runtime[DEVICE.lstrip("/") + "/identity"]
    app_files[app_prefix + "tar"] = ((HERE / "assets/tar").read_bytes(), 0o755)
    return app_files


def create_session(directory, product, board, version, build, ecid):
    validate_target(product, board, version, build)
    if not re.fullmatch(r"[1-9][0-9]{0,19}", ecid) or int(ecid) >= 2**64:
        raise ImageError("ECID must be a nonzero unsigned 64-bit decimal number")
    directory = Path(directory).resolve()
    directory.mkdir(mode=0o700)
    session = str(uuid.uuid4())
    files, runtime_audit, manifest = runtime_files(HERE.parent)
    public = keygen(directory / "client_rsa", "lik-ios10-client-" + session)
    server = keygen(directory / "host_rsa", "lik-ios10-host-" + session)
    (directory / "known_hosts").write_text("lik-ios10-" + session + " " + server + "\n")
    (directory / "payload_jumpstart").write_bytes((HERE / "assets/payload_jumpstart").read_bytes())
    info = dict(schema=1, session=session, ecid=ecid, product=product, board=board, version=version, build=build)
    app_files = restore_files(directory, info, files, public)
    (directory / "runtime.tar").write_bytes(app_files["Applications/LIKTools.app/runtime.tar"][0])
    validate_runtime(directory / "runtime.tar")
    stage = directory / "stage.tar"
    add_archive(stage, app_files)
    validate_stage(stage)
    info.update(phase="staged", stage_sha256=digest(stage), runtime=runtime_audit, installer="socket-system",
                assets_sha256=manifest["sha256"], restore_enabled=False, hardware_tested=False)
    write_json(directory / "session.json", info)
    return info


def main():
    p = argparse.ArgumentParser(description=__doc__)
    for name in ("directory", "product", "board", "version", "build", "ecid"):
        p.add_argument("--" + name, required=True)
    a = p.parse_args()
    info = create_session(a.directory, a.product, a.board, a.version, a.build, a.ecid)
    print("Prepared offline session " + info["session"] + "; no device contacted.")


if __name__ == "__main__":
    main()
