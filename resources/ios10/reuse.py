#!/usr/bin/env python3
"""Validate and reuse a prepared image in a new, separately journaled attempt."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tarfile
import zipfile

from macho import ImageError
from prepare import (IMAGE_RECIPE, JUMP_BOOT_ARGS, RESTORE_BOOT_ARGS, Runner,
                     digest, patch_boot_component, prepare_restore_components, rewrite_zip,
                     select_identity, validate_stage, write_json)
from progress import Progress
from session import Session, verify_image_checksum
from stage import HERE, runtime_files, restore_files
from allinone_stage import compose, name as package_name

REUSABLE_PHASES = ('image-ready', 'restore-failed')


def source_manifest(ipsw, target):
    with zipfile.ZipFile(ipsw) as archive:
        raw = archive.read('BuildManifest.plist')
    select_identity(plistlib.loads(raw), *(target[k] for k in ('product', 'board', 'version', 'build')))
    return raw


def compatible(session, target, manifest_bytes):
    if session.data.get('phase') not in REUSABLE_PHASES:
        return False
    if any(session.data.get(k) != v for k, v in target.items()):
        return False
    record = Path(session.data['preparation'])
    if record.resolve().parent != session.directory / 'image' or digest(record) != session.data['preparation_sha256']:
        return False
    info = json.loads(record.read_text())
    assets = json.loads((HERE / 'assets/manifest.json').read_text())['sha256']
    # Reuse consumes no stock filesystem bytes. Match its small manifest here;
    # an upgrade separately hashes every source component that it actually uses.
    return (info.get('phase') == 'image-prepared'
            and (record.parent / 'BuildManifest.plist').read_bytes() == manifest_bytes
            and info.get('recipe') == IMAGE_RECIPE
            and session.data.get('assets_sha256') == assets)


def candidates(parent, target, ipsw):
    manifest_bytes = source_manifest(ipsw, target)
    found = []
    for directory in Path(parent).glob(target['ecid'] + '-*'):
        try:
            session = Session(directory)
            if compatible(session, target, manifest_bytes):
                found.append(directory)
        except (ImageError, OSError, ValueError, KeyError):
            continue
    return sorted(found, key=lambda p: p.stat().st_mtime, reverse=True)


def verify_stage(session):
    """Regenerate the expected file map with the image's existing credentials.

    Reuse is rejected if installer scripts, runtime, packages or configuration
    differ. Private key contents are compared locally and never logged.
    """
    if session.data.get('installer')=='restore-allinone':
        files,_=compose(session.data)
        with tarfile.open(session.directory/'stage.tar') as archive:
            actual={package_name(m.name):m for m in archive}
            # Generated parent directories are checked separately by validate_stage.
            validate_stage(session.directory/'stage.tar')
            for n,(m,data) in files.items():
                old=actual.pop(n,None)
                if old is None or (old.type,old.mode,old.uid,old.gid,old.linkname)!=(m.type,m.mode,m.uid,m.gid,m.linkname):
                    raise ImageError('Prepared image metadata changed: '+n)
                if m.isfile() and archive.extractfile(old).read()!=data:
                    raise ImageError('Prepared image contents changed: '+n)
            if any(not m.isdir() for m in actual.values()):raise ImageError('Unexpected extra staged file')
        return
    directory = session.directory
    keys = {}
    for name in ('client_rsa', 'host_rsa'):
        derived = subprocess.run(['ssh-keygen', '-y', '-f', str(directory / name)],
                                 stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10)
        public = (directory / (name + '.pub')).read_text().split()[:2]
        if derived.returncode or derived.stdout.decode().split()[:2] != public:
            raise ImageError('Saved installer key pair does not match: ' + name)
        keys[name] = ' '.join(public)
    expected_host = 'lik-ios10-' + session.data['session'] + ' ' + keys['host_rsa'] + '\n'
    if (directory / 'known_hosts').read_text() != expected_host:
        raise ImageError('Saved installer host key does not match')
    info = {k: session.data[k] for k in ('schema', 'session', 'ecid', 'product', 'board', 'version', 'build')}
    files, _, _ = runtime_files(HERE.parent)
    files = restore_files(directory, info, files, keys['client_rsa'])
    actual = {k: v for k, v in validate_stage(directory / 'stage.tar').items() if v is not None}
    expected = {name: hashlib.sha256(data).hexdigest() for name, (data, _) in files.items()}
    if actual != expected:
        raise ImageError('Prepared image contains different installer files; choose a fresh build')
    with tarfile.open(directory / 'stage.tar') as archive:
        for member in archive:
            if member.name in files and member.mode != files[member.name][1]:
                raise ImageError('Prepared installer file permissions changed')


def clone_attempt(old_directory, new_directory, ipsw, tools, target):
    old = Session(old_directory)
    if not compatible(old, target, source_manifest(ipsw, target)):
        raise ImageError('Saved image is not compatible with this restore')
    old.verify_boot_artifacts()
    verify_stage(old)
    info = json.loads(Path(old.data['preparation']).read_text())
    if info.get('recipe') != IMAGE_RECIPE:
        verify_image_checksum(old.data['image'], old.data['image_sha256'])
    new = Path(new_directory).resolve()
    new.mkdir(mode=0o700)
    try:
        clone_checked(old, new, ipsw, tools, info)
    except BaseException:
        # Only the newly-created attempt is removed. Historical evidence stays.
        shutil.rmtree(new)
        raise


def clone_checked(old, new, ipsw, tools, info):
    work = new / 'image'
    work.mkdir(mode=0o700)
    names=('stage.tar',) if old.data.get('installer')=='restore-allinone' else ('client_rsa','client_rsa.pub','host_rsa','host_rsa.pub','known_hosts','stage.tar','payload_jumpstart')
    for name in names:shutil.copy2(old.directory/name,new/name)
    old_work=Path(old.data['preparation']).parent
    names=('BuildManifest.plist','BuildIdentity.plist','iBSS.restore.img3','iBSS.restore.patched')
    if old.data.get('installer')!='restore-allinone':names+=('iBEC.jumpstart.img3',)
    for name in names:shutil.copy2(old_work/name,work/name)
    output = new / 'custom.ipsw'
    if info.get('recipe') == IMAGE_RECIPE:
        # Immutable image: create a separate directory entry without duplicating
        # gigabytes. No code ever edits a prepared IPSW in place.
        try:
            os.link(old.data['image'], output)
        except OSError:
            shutil.copy2(old.data['image'], output)
        print('Reusing custom IPSW; no filesystem extraction or compression needed.', flush=True)
    else:
        if shutil.disk_usage(new).free < Path(old.data['image']).stat().st_size + 256 * 1024**2:
            raise ImageError('Not enough free disk space to refresh the reused IPSW restore components')
        print('Reusing prepared filesystem. Updating temporary restore components.', flush=True)
        original = work / 'iBEC.original'
        component_path = info['components']['iBEC']['path']
        kernel = work / 'KernelCache.original'
        with zipfile.ZipFile(ipsw) as z:
            original.write_bytes(z.read(component_path))
            kernel.write_bytes(z.read(info['components']['KernelCache']['path']))
        if digest(original) != info['components']['iBEC']['sha256']:
            raise ImageError('Source iBEC does not match the saved image')
        if digest(kernel) != info['components']['KernelCache']['sha256']:
            raise ImageError('Source kernel does not match the saved image')
        runner = Runner(tools, work / 'tools.log')
        with Progress('Preparing restore and temporary-boot loaders', 8, 'steps') as progress:
            ibec = patch_boot_component(runner, original, work / 'iBEC.restore.img3',
                                        ['--rsa', '--debug', '-b', RESTORE_BOOT_ARGS], progress)
            patch_boot_component(runner, original, work / 'iBEC.jumpstart.img3',
                                 ['--rsa', '--debug', '-b', JUMP_BOOT_ARGS, '-c', 'go', '0x80000000',
                                  '--remote-boot', '--boot-partition', '--boot-ramdisk'], progress)
        manifest = plistlib.loads((work / 'BuildManifest.plist').read_bytes())
        identity = select_identity(manifest, *(info[k] for k in ('product', 'board', 'version', 'build')))
        replacements, audit = prepare_restore_components(runner, kernel, work, manifest, identity)
        replacements[component_path] = ibec
        rewrite_zip(Path(old.data['image']), output, replacements)
        info['restore_kernel_patch'] = audit
        info['replacements'].update({name: digest(path) for name, path in replacements.items()})
        info['output_sha256'] = digest(output, label='Recording refreshed IPSW checksum')
        info['jumpstart_ibec_sha256'] = digest(work / 'iBEC.jumpstart.img3')
        info['boot_artifacts']['iBEC.jumpstart.img3'] = info['jumpstart_ibec_sha256']
    info.update(recipe=IMAGE_RECIPE, output=str(output), reused_from=str(old.directory))
    write_json(work / 'preparation.json', info)
    data = dict(old.data)
    for key in ('image', 'image_sha256', 'image_verification', 'space_check', 'preparation',
                'preparation_sha256', 'restorer_exit_code', 'history'):
        data.pop(key, None)
    data.update(phase='staged', reused_from=str(old.directory), history=[])
    write_json(new / 'session.json', data)
    Session(new).register_image(work / 'preparation.json')
    Session(new).verify_boot_artifacts()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('list', 'clone'))
    for name in ('ipsw', 'product', 'board', 'version', 'build', 'ecid'):
        parser.add_argument('--' + name, required=True)
    for name in ('parent', 'old', 'new', 'tools'):
        parser.add_argument('--' + name)
    a = parser.parse_args()
    target = {k: getattr(a, k) for k in ('product', 'board', 'version', 'build', 'ecid')}
    if a.action == 'list':
        for directory in candidates(a.parent, target, a.ipsw):
            print(directory)
    else:
        os.umask(0o077)
        clone_attempt(a.old, a.new, a.ipsw, a.tools, target)


if __name__ == '__main__':
    try:
        main()
    except (ImageError, OSError, ValueError, KeyError, zipfile.BadZipFile, subprocess.SubprocessError) as exc:
        raise SystemExit(str(exc))
