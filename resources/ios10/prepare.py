#!/usr/bin/env python3
"""Offline image preparation. Never communicates with a device.

Uses Kit's existing xpwntool, iBoot32Patcher, hfsplus and dmg binaries. The
unmodified IPSW remains the source of persistent iBoot, kernel and dyld assets.
All modifications and tool output are recorded beside the generated image.
"""

import argparse
import copy
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import plistlib
import re
import shutil
import subprocess
import sys
import tarfile
import zipfile

from macho import ImageError, patch_asr
from progress import Progress, DmgProgress, dmg_extract_size, stream_tool
from memory import ram_workspace
from restore_kernel import prepare_restore_kernel
from udif import materialize_hfs_zeros

MIB = 1024 * 1024
# Board names are cross-checked against the selected IPSW's erase identity.
BOARDS = {"iPhone5,1": "n41ap", "iPhone5,2": "n42ap", "iPhone5,3": "n48ap",
          "iPhone5,4": "n49ap", "iPad3,4": "p101ap", "iPad3,5": "p102ap",
          "iPad3,6": "p103ap"}
BOOT_ARGS = "cs_enforcement_disable=1 amfi_get_out_of_my_way=1 amfi=0xff"
SERIAL_BOOT_ARGS = "serial=3 debug=0x14"
RESTORE_BOOT_ARGS = "rd=md0 nand-enable-reformat=1 -progress -restore " + BOOT_ARGS + " " + SERIAL_BOOT_ARGS
JUMP_BOOT_ARGS = BOOT_ARGS + " lik_ios10_jumpstart=1 " + SERIAL_BOOT_ARGS
IMAGE_RECIPE = 11
RESTORE_KERNEL_PATH = "Downgrade/LIKRestoreKernelCache"
STAGE_ROOTS = ("Applications/LIKTools.app",)
RUNTIME_ROOTS = ("usr/local/share/lik-ios10", "usr/lik")
TRANSPORT_PLIST = "Library/LaunchDaemons/org.legacyioskit.ios10.transport.plist"
DIAGNOSTICS_PLIST = "System/Library/LaunchDaemons/org.legacyioskit.ios10.diagnostics.plist"


def validate_target(product, board, version, build):
    if BOARDS.get(product) != board:
        raise ImageError("ProductType and HardwareModel do not match an A6/A6X target")
    # The _103 payload finders are not established on earlier iOS 10 releases.
    if (version, build) not in (("10.3.3", "14G60"), ("10.3.4", "14G61")):
        raise ImageError("The initial image preparer is limited to 10.3.3/10.3.4")
    # Model coverage comes from the actual IPSW below, not download catalogues.
    # Apple's 14G61 iPhone manifest includes BOTH iPhone 5c boards (n48/n49).


def archive_name(name):
    # Keep compatibility with Python 3.7/3.8 on older supported macOS versions.
    return name[2:] if name.startswith("./") else name


def digest(path, algorithm="sha256", progress=None, label=None):
    if label is not None:
        with Progress(label, Path(path).stat().st_size) as display:
            return digest(path, algorithm, progress=display)
    h = hashlib.new(algorithm)
    with Path(path).open("rb") as f:
        for block in iter(lambda: f.read(MIB), b""):
            h.update(block)
            if progress is not None:
                progress.advance(len(block))
    return h.hexdigest()


def digest_files(paths, label):
    with Progress(label, sum(Path(p).stat().st_size for p in paths.values())) as progress:
        return {key: digest(path, progress=progress) for key, path in paths.items()}


def copy_stream(source, target, progress):
    for block in iter(lambda: source.read(MIB), b""):
        target.write(block)
        progress.advance(len(block))


def write_json(path, data):
    path = Path(path)
    temp = path.with_suffix(path.suffix + ".tmp")
    with temp.open("w") as f:
        json.dump(data, f, indent=2, sort_keys=True)
        f.write("\n")
        f.flush()
        os.fsync(f.fileno())
    temp.replace(path)


def select_identity(manifest, product, board, version, build):
    validate_target(product, board, version, build)
    if manifest.get("ProductVersion") != version or manifest.get("ProductBuildVersion") != build:
        raise ImageError("IPSW version/build does not match the requested target")
    if product not in manifest.get("SupportedProductTypes", []):
        raise ImageError("IPSW does not support this ProductType")
    candidates = [ident for ident in manifest.get("BuildIdentities", [])
                  if ident.get("Info", {}).get("DeviceClass") == board
                  and ident.get("Info", {}).get("RestoreBehavior") == "Erase"]
    if len(candidates) != 1:
        raise ImageError("Expected exactly one erase BuildIdentity for this board")
    ident = candidates[0]
    for key in ("OS", "iBSS", "iBEC", "RestoreRamDisk", "KernelCache", "iBoot"):
        value = ident.get("Manifest", {}).get(key, {})
        path = value.get("Info", {}).get("Path", "")
        if not path or PurePosixPath(path).is_absolute() or ".." in PurePosixPath(path).parts:
            raise ImageError("Invalid or missing component path: " + key)
    return ident


class Runner:
    def __init__(self, tools, log):
        self.tools = Path(tools).resolve()
        self.log = Path(log)

    def run(self, name, *args, on_line=None):
        command = [str(self.tools / name), *map(str, args)]
        if on_line is None:
            completed = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        else:
            completed = stream_tool(command, on_line)
        output = completed.stdout.decode("utf-8", errors="replace")
        with self.log.open("a") as f:
            f.write(json.dumps({"argv": command, "exit_code": completed.returncode}) + "\n")
            f.write(output + "\n")
        # This bundled patcher deliberately returns 1 after writing its output.
        success = (completed.returncode == 1 and "main: Quitting..." in output
                   and "Error" not in output) if name == "iBoot32Patcher" else completed.returncode == 0
        if not success:
            raise ImageError(f"{name} failed; see {self.log}")
        return output

    def dmg(self, operation, source, target, label):
        total = hfs_size(source)[0] if operation == "build" else dmg_extract_size(source)
        with Progress(label, total or 1, "bytes" if total else "steps") as progress:
            self.run("dmg", operation, source, target, on_line=DmgProgress(progress, operation))

    def extract_hfs(self, image, path, output):
        output = Path(output)
        if output.exists():
            output.unlink()
        self.run("hfsplus", image, "extract", path, output)
        if not output.is_file() or not output.stat().st_size:
            raise ImageError("HFS extraction produced no file: " + path)
        return output


def hfs_size(path):
    with Path(path).open("rb") as f:
        f.seek(1024)
        header = f.read(52)
    import struct
    if header[:2] not in (b"H+", b"HX") or len(header) < 52:
        raise ImageError("Expected a raw HFS+ volume")
    block, total, free = struct.unpack_from(">III", header, 40)
    if not block or block & (block - 1) or free > total:
        raise ImageError("Invalid HFS+ volume size")
    return block * total, block * free


def validate_legacy_stage(path):
    """The restore may add only the Socket app; no active bootstrap or daemon."""
    entries = {}
    with tarfile.open(path) as archive:
        for member in archive:
            name = archive_name(member.name).rstrip("/")
            if (not name or PurePosixPath(name).is_absolute() or ".." in PurePosixPath(name).parts
                    or name in entries):
                raise ImageError("Unsafe or duplicate app archive path")
            root = STAGE_ROOTS[0]
            if name != "Applications" and name != root and not name.startswith(root + "/"):
                raise ImageError("The restore stage may only add the Socket app")
            if member.uid != 0 or member.gid != 0 or member.mode & 0o7022:
                raise ImageError("App files must be root owned with normal permissions")
            if not (member.isfile() or member.isdir()):
                raise ImageError("App stage links and devices are not allowed")
            if name in ("Applications", root) and not member.isdir():
                raise ImageError("App parent must be a directory")
            if name != "Applications" and str(PurePosixPath(name).parent) not in entries:
                raise ImageError("App archive must create parents first")
            entries[name] = hashlib.sha256(archive.extractfile(member).read()).hexdigest() if member.isfile() else None
    required = ("LIKTools", "Info.plist", "identity", "runtime.tar", "runtime.sha256", "tar")
    if any(not entries.get(STAGE_ROOTS[0] + "/" + name) for name in required):
        raise ImageError("Incomplete Socket app bundle")
    return entries


def validate_stage(path):
    # Legacy archives remain inspectable, but prepare_image only accepts AIO.
    with tarfile.open(path) as t:
        is_aio=any(archive_name(m.name)=='usr/local/share/lik-aio/plan.plist' for m in t)
    if not is_aio:return validate_legacy_stage(path)
    entries={}
    with tarfile.open(path) as t:
        for m in t:
            n=archive_name(m.name).rstrip('/')
            if not n or n.startswith('/') or '..' in PurePosixPath(n).parts or n in entries:
                raise ImageError('Unsafe all-in-one archive entry')
            if n=='private/var' or n.startswith(('private/var/','var/','System/')):
                raise ImageError('Data and stock System files must not be overlaid by ASR')
            if m.isfile():entries[n]=hashlib.sha256(t.extractfile(m).read()).hexdigest()
            elif m.isdir():entries[n]=None
            elif m.issym():entries[n]={'link':m.linkname}
            else:raise ImageError('Unsupported all-in-one archive entry')
    for n in ('bin/bash','bin/launchctl','Applications/Zebra.app/Zebra','usr/bin/procyon','usr/local/share/lik-aio/plan.plist'):
        if not entries.get(n):raise ImageError('Incomplete all-in-one system stage: '+n)
    return entries


def validate_runtime(path):
    """Only installer-owned paths may be added before the automatic first boot.

    /var data and the Procyon boot trigger are deliberately absent. Only the
    private transport/diagnostic runtime, their daemons, the diagnostic app,
    and the missing /bin/sh are allowed.
    """
    entries = {}
    with tarfile.open(path) as tar:
        for member in tar:
            name = archive_name(member.name).rstrip("/")
            parts = PurePosixPath(name).parts
            if not name or PurePosixPath(name).is_absolute() or ".." in parts:
                raise ImageError("Unsafe staging archive path")
            if name in entries:
                raise ImageError("Duplicate staging archive path: " + name)
            shared_parents = ("usr", "usr/local", "usr/local/share", "bin", "Library", "Library/LaunchDaemons", "System", "System/Library", "System/Library/LaunchDaemons", "Applications")
            private = any(name == root or name.startswith(root + "/") for root in RUNTIME_ROOTS)
            if name not in (*shared_parents, TRANSPORT_PLIST, DIAGNOSTICS_PLIST, "bin/sh") and not private:
                raise ImageError("Staging archive changes a path outside its installer directory")
            if name in shared_parents and not member.isdir():
                raise ImageError("Shared staging parents must be directories")
            if name in RUNTIME_ROOTS and not member.isdir():
                raise ImageError("Private staging roots must be directories")
            if member.uid != 0 or member.gid != 0 or member.mode & 0o7022:
                raise ImageError("Staging content must be root owned without special or write-for-all modes")
            if name == "bin/sh":
                if not member.issym() or member.linkname != "/usr/lik/bash":
                    raise ImageError("Only the private bootstrap shell symlink is allowed")
                entries[name] = hashlib.sha256(member.linkname.encode()).hexdigest()
                continue
            if not (member.isfile() or member.isdir()):
                raise ImageError("Staging archive links/devices are unsupported")
            parent = str(PurePosixPath(name).parent)
            if (private and name not in RUNTIME_ROOTS or name in (TRANSPORT_PLIST, DIAGNOSTICS_PLIST)) and parent not in entries:
                raise ImageError("Staging archive must create parent directories before their files")
            entries[name] = None if member.isdir() else hashlib.sha256(tar.extractfile(member).read()).hexdigest()
    if not any(value for value in entries.values()):
        raise ImageError("Empty staging archive")
    return entries


def patch_boot_component(runner, source, output, flags, progress=None):
    raw = output.with_suffix(".raw")
    patched = output.with_suffix(".patched")
    runner.run("xpwntool", source, raw)
    if not raw.is_file() or raw.stat().st_size < 4096:
        raise ImageError("Bootloader extraction failed")
    if progress is not None:
        progress.advance()
    runner.run("iBoot32Patcher", raw, patched, *flags)
    if not patched.is_file() or patched.stat().st_size != raw.stat().st_size or digest(patched) == digest(raw):
        raise ImageError("Bootloader patch was empty or changed the component size")
    if progress is not None:
        progress.advance()
    runner.run("xpwntool", patched, output, "-t", source)
    if progress is not None:
        progress.advance()
    roundtrip = output.with_suffix(".roundtrip")
    runner.run("xpwntool", output, roundtrip)
    if not roundtrip.is_file() or digest(roundtrip) != digest(patched):
        raise ImageError("Bootloader container round trip failed")
    if progress is not None:
        progress.advance()
    return output


def verify_staging(runner, root, entries, check, progress=None):
    for name, expected in entries.items():
        if not expected:
            continue
        if isinstance(expected,dict):
            listing=runner.run("hfsplus",root,"ls","-l",name)
            if not any(line.endswith(" "+name+" -> "+expected['link']) for line in listing.splitlines()):
                raise ImageError("Staged symlink verification failed: "+name)
            if progress is not None:progress.advance()
            continue
        if name == "bin/sh":
            # hfsplus extract follows symlinks. Inspect the actual link with
            # ls -l, then verify that dereferencing it yields our private shell.
            listing = runner.run("hfsplus", root, "ls", "-l", name)
            if not re.search(r"^l[^\n]* bin/sh -> /usr/lik/bash$", listing, re.M):
                raise ImageError("System staging shell symlink verification failed")
            expected = entries.get("usr/lik/bash")
            if not expected:
                raise ImageError("Staged shell target is missing")
        if check.exists():check.unlink()
        runner.run('hfsplus',root,'extract',name,check)
        if not check.is_file():raise ImageError('Staged file missing: '+name)
        if digest(check) != expected:
            raise ImageError("System staging verification failed: " + name)
        if progress is not None:
            progress.advance()


def rewrite_zip(source, output, replacements):
    if output.exists():
        raise ImageError("Refusing to overwrite an existing IPSW")
    temp = output.with_suffix(".partial")
    if temp.exists():
        raise ImageError("An unfinished output already exists: " + str(temp))
    with zipfile.ZipFile(source) as original, zipfile.ZipFile(temp, "w", allowZip64=True) as result:
        additions = set(replacements) - set(original.namelist())
        for name in additions:
            if PurePosixPath(name).is_absolute() or ".." in PurePosixPath(name).parts:
                raise ImageError("Unsafe added IPSW component path")
        total = sum(Path(replacements[i.filename]).stat().st_size if i.filename in replacements else i.file_size
                    for i in original.infolist()) + sum(Path(replacements[n]).stat().st_size for n in additions)
        with Progress("Packaging custom IPSW", total) as progress:
            for info in original.infolist():
                inp = Path(replacements[info.filename]).open("rb") if info.filename in replacements else original.open(info)
                with inp, result.open(copy.copy(info), "w", force_zip64=True) as out:
                    copy_stream(inp, out, progress)
            for name in sorted(additions):
                with Path(replacements[name]).open("rb") as inp, result.open(name, "w", force_zip64=True) as out:
                    copy_stream(inp, out, progress)
    # A complete CRC pass catches truncated streams before advertising an image.
    # ZipExtFile checks each CRC at EOF, as testzip() did, while letting us count
    # verified bytes. Keep the separate replacement-content checks as well.
    with zipfile.ZipFile(temp) as z:
        with Progress("Verifying custom IPSW archive", sum(i.file_size for i in z.infolist())) as progress:
            for info in z.infolist():
                with z.open(info) as f:
                    for block in iter(lambda: f.read(MIB), b""):
                        progress.advance(len(block))
        total = sum(z.getinfo(name).file_size + Path(path).stat().st_size for name, path in replacements.items())
        with Progress("Verifying replaced IPSW components", total) as progress:
            for name, path in replacements.items():
                h = hashlib.sha256()
                with z.open(name) as f:
                    for block in iter(lambda: f.read(MIB), b""):
                        h.update(block)
                        progress.advance(len(block))
                if h.hexdigest() != digest(path, progress=progress):
                    raise ImageError("Generated IPSW component verification failed: " + name)
    temp.replace(output)


def prepare_restore_components(runner, source_kernel, work, manifest, identity):
    """Use a separate patched kernel during restore; keep installed iOS stock."""
    paths = identity["Manifest"]
    if paths["RestoreKernelCache"]["Info"]["Path"] != paths["KernelCache"]["Info"]["Path"]:
        raise ImageError("This image builder expects the shared iOS 10 source kernel")
    output = work / "RestoreKernelCache.modified"
    with Progress("Preparing temporary restore kernel", 1, "steps") as progress:
        audit = prepare_restore_kernel(runner, source_kernel, output)
        progress.advance()
    custom_manifest = copy.deepcopy(manifest)
    index = manifest["BuildIdentities"].index(identity)
    custom_manifest["BuildIdentities"][index]["Manifest"]["RestoreKernelCache"]["Info"]["Path"] = RESTORE_KERNEL_PATH
    # Preserve Apple's component digests for current-nonce ticket negotiation.
    # Only the temporary component's archive path changes, like upstream's
    # separate Downgrade/RestoreKernelCache. KernelCache stays at its stock path.
    custom_path = work / "BuildManifest.custom.plist"
    custom_path.write_bytes(plistlib.dumps(custom_manifest))
    return {RESTORE_KERNEL_PATH: output, "BuildManifest.plist": custom_path}, audit


def prepare(args):
    with ram_workspace(getattr(args, 'memory', False), args.work) as scratch:
        return prepare_image(args, scratch)


def prepare_image(args, scratch):
    source, output, work = Path(args.ipsw).resolve(), Path(args.output).resolve(), Path(args.work).resolve()
    if source == output or output.exists() or work.exists():
        raise ImageError("Use a new output IPSW and a new work directory")
    stage = Path(args.stage).resolve()
    stage_entries = validate_stage(stage)
    if 'usr/local/share/lik-aio/plan.plist' not in stage_entries:
        raise ImageError('This builder requires a fresh all-in-one stage')
    with zipfile.ZipFile(source) as z:
        if len(z.namelist()) != len(set(z.namelist())):
            raise ImageError("IPSW contains duplicate paths")
        manifest_bytes = z.read("BuildManifest.plist")
        manifest = plistlib.loads(manifest_bytes)
        identity = select_identity(manifest, args.product, args.board, args.version, args.build)
        paths = {key: value.get("Info", {}).get("Path") for key, value in identity["Manifest"].items()}
        for key in ("OS", "iBSS", "iBEC", "RestoreRamDisk", "KernelCache", "iBoot"):
            if paths[key] not in z.namelist():
                raise ImageError("IPSW is missing " + key)
        required_gib = 8 if getattr(args, 'memory', False) else 18
        if shutil.disk_usage(output.parent).free < required_gib * 1024**3:
            raise ImageError(f"At least {required_gib} GiB free disk space is required for image preparation")
        work.mkdir(parents=True, mode=0o700)
        (work / "BuildManifest.plist").write_bytes(manifest_bytes)
        (work / "BuildIdentity.plist").write_bytes(plistlib.dumps(identity))
        components = {}
        for key in ("OS", "iBSS", "iBEC", "RestoreRamDisk", "KernelCache", "iBoot"):
            target = work / (key + ".original")
            with Progress("Extracting " + key, z.getinfo(paths[key]).file_size) as progress:
                with z.open(paths[key]) as inp, target.open("wb") as out:
                    copy_stream(inp, out, progress)
            components[key] = target
    runner = Runner(args.tools, work / "tools.log")
    restore_replacements, kernel_audit = prepare_restore_components(
        runner, components["KernelCache"], work, manifest, identity)
    source_sha = digest(source, label="Verifying source IPSW checksum")
    component_sha = digest_files(components, "Verifying extracted components")
    state = {"schema": 1, "phase": "preparing", "product": args.product, "board": args.board,
             "version": args.version, "build": args.build, "input": str(source),
             "output": str(output), "stage_sha256": digest(stage),
             "source_sha256": source_sha, "components": {key: {"path": paths[key], "sha256": component_sha[key]}
                                                             for key, path in components.items()},
             "hardware_tested": False, "restore_enabled": False}
    write_json(work / "preparation.json", state)
    with Progress("Preparing restore loaders", 8, "steps") as progress:
        ibss = patch_boot_component(runner, components["iBSS"], work / "iBSS.restore.img3", ["--rsa"], progress)
        ibec = patch_boot_component(runner, components["iBEC"], work / "iBEC.restore.img3",
                                    ["--rsa", "--debug", "-b", RESTORE_BOOT_ARGS], progress)
    root, ramdisk = scratch / "rootfs.raw", work / "ramdisk.raw"
    runner.dmg("extract", components["OS"], root, "Extracting unencrypted system filesystem")
    old_size, _ = hfs_size(root)
    # hfsplus returns zero even for a missing HFS path; inspect its diagnostic.
    # Refuse to replace any pre-existing installation or stock shell/service.
    for path in ("usr/local/share/lik-aio", "Applications/Zebra.app", "usr/bin/procyon"):
        if "No such file or directory" not in runner.run("hfsplus", root, "ls", path):
            raise ImageError("Installer staging path already exists in the source IPSW: " + path)
    # Preserve the existing +160 MiB policy for the bootstrap and untether.
    new_mb = (old_size + MIB - 1) // MIB + 160
    with Progress("Preparing system filesystem", 2, "steps") as progress:
        runner.run("hfsplus", root, "grow", new_mb * MIB)
        if hfs_size(root)[0] < new_mb * MIB:
            raise ImageError("System filesystem growth failed")
        progress.advance()
        runner.run("hfsplus", root, "untar", stage)
        progress.advance()
    check = work / "check-file"
    with Progress("Verifying staged installer files", sum(bool(v) for v in stage_entries.values()), "steps") as progress:
        verify_staging(runner, root, stage_entries, check, progress)
    with Progress("Preparing restore ramdisk", 6, "steps") as progress:
        runner.run("xpwntool", components["RestoreRamDisk"], ramdisk)
        old_ramdisk_size,_=hfs_size(ramdisk)
        runner.run("hfsplus",ramdisk,"grow",old_ramdisk_size+8*MIB)
        # The wrapper is called only by restored's late bootdelay=0 operation.
        # Installed nvram, iBoot and kernel remain stock.
        native=Path(__file__).resolve().parent/'assets'
        stock_nvram=runner.extract_hfs(ramdisk,'usr/sbin/nvram',work/'nvram.stock')
        runner.run('hfsplus',ramdisk,'add',stock_nvram,'usr/sbin/nvram.stock')
        for source_file,destination in (('allinone-nvram','usr/sbin/nvram'),('allinone-lik-restore-finalize','usr/local/bin/lik-restore-finalize')):
            runner.run('hfsplus',ramdisk,'add',native/source_file,destination)
            runner.run('hfsplus',ramdisk,'chmod','755',destination)
            runner.run('hfsplus',ramdisk,'chown','0:0',destination)
            runner.extract_hfs(ramdisk,destination,check)
            if digest(check)!=digest(native/source_file):raise ImageError('Restore finalizer verification failed')
        runner.run('hfsplus',ramdisk,'chmod','755','usr/sbin/nvram.stock')
        progress.advance()
        asr = runner.extract_hfs(ramdisk, "usr/sbin/asr", work / "asr.original")
        modified, asr_audit = patch_asr(asr.read_bytes())
        (work / "asr.patched").write_bytes(modified)
        progress.advance()
        runner.run("hfsplus", ramdisk, "add", work / "asr.patched", "usr/sbin/asr")
        runner.run("hfsplus", ramdisk, "chmod", "755", "usr/sbin/asr")
        runner.run("hfsplus", ramdisk, "chown", "0:0", "usr/sbin/asr")
        runner.extract_hfs(ramdisk, "usr/sbin/asr", check)
        if check.read_bytes() != modified:
            raise ImageError("ASR ramdisk verification failed")
        progress.advance()
        options_path = "usr/local/share/restore/options." + args.board[:-2] + ".plist"
        options_file = runner.extract_hfs(ramdisk, options_path, work / "options.original.plist")
        options = plistlib.loads(options_file.read_bytes())
        options.update(MinimumSystemPartition=new_mb, SystemPartitionSize=new_mb,
                       CreateFilesystemPartitions=True, UpdateBaseband=not args.no_baseband)
        options_new = work / "options.patched.plist"
        options_new.write_bytes(plistlib.dumps(options))
        progress.advance()
        runner.run("hfsplus", ramdisk, "add", options_new, options_path)
        runner.extract_hfs(ramdisk, options_path, check)
        if plistlib.loads(check.read_bytes()) != options:
            raise ImageError("Restore-options verification failed")
        progress.advance()
        ramdisk_out = work / "RestoreRamDisk.modified"
        runner.run("xpwntool", ramdisk, ramdisk_out, "-t", components["RestoreRamDisk"])
        runner.run("xpwntool", ramdisk_out, work / "ramdisk.roundtrip")
        if digest(ramdisk) != digest(work / "ramdisk.roundtrip"):
            raise ImageError("Restore ramdisk container round trip failed")
        progress.advance()
    root_out = work / "OS.modified.dmg"
    runner.dmg("build", root, root_out, "Compressing modified system filesystem")
    explicit_zeros = work / "OS.explicit-zeros.dmg"
    with Progress("Preparing zero-filled regions for restore", root.stat().st_size) as progress:
        zero_audit = materialize_hfs_zeros(root_out, explicit_zeros, root, progress)
    explicit_zeros.replace(root_out)
    # Verify the rebuilt compressed image as HFS, including every staged file.
    runner.dmg("extract", root_out, scratch / "rootfs.roundtrip", "Extracting rebuilt filesystem for verification")
    checksums = digest_files({"original": root, "rebuilt": scratch / "rootfs.roundtrip"}, "Verifying system filesystem round trip")
    if checksums["original"] != checksums["rebuilt"]:
        raise ImageError("System disk-image round trip failed")
    replacements = {paths["OS"]: root_out, paths["iBSS"]: ibss, paths["iBEC"]: ibec,
                    paths["RestoreRamDisk"]: ramdisk_out}
    replacements.update(restore_replacements)
    print("Packaging and verifying custom IPSW", flush=True)
    rewrite_zip(source, output, replacements)
    output_sha = digest(output, label="Calculating final IPSW checksum")
    replacement_sha = digest_files(replacements, "Recording component checksums")
    state.update(phase="image-prepared", recipe=IMAGE_RECIPE, output_sha256=output_sha, system_partition_mb=new_mb,
                 restore_zero_fill=zero_audit,
                 asr_patch=asr_audit, restore_kernel_patch=kernel_audit, replacements=replacement_sha,
                 boot_artifacts={name: digest(work / name) for name in
                                 ("iBSS.restore.img3", "iBSS.restore.patched")},
                 installer="restore-allinone",
                 limitations=["First all-in-one hardware test pending", "Ordinary boot must be verified on the device"])
    write_json(work / "preparation.json", state)
    print("Custom IPSW prepared and verified.", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("ipsw", "output", "work", "stage", "tools", "product", "board", "version", "build"):
        parser.add_argument("--" + name, required=True)
    parser.add_argument("--no-baseband", action="store_true")
    parser.add_argument("--memory", action="store_true", help="Use RAM for uncompressed system images")
    args = parser.parse_args()
    try:
        prepare(args)
    except (ImageError, OSError, ValueError, zipfile.BadZipFile, tarfile.TarError) as exc:
        print("Image preparation failed: " + str(exc), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
