import json
import os
from pathlib import Path
import plistlib
import shutil
import sys
import tempfile
import unittest
import zipfile
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'resources/ios10'))
from prepare import IMAGE_RECIPE, digest, write_json
from reuse import candidates, clone_attempt, compatible, source_manifest, verify_stage
from stage import create_session
from session import Session
from macho import ImageError


class ReuseTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        cls.base = Path(cls.tmp.name)
        cls.old = cls.base / '12345-old'
        cls.target = dict(product='iPhone5,4', board='n49ap', version='10.3.4', build='14G61', ecid='12345')
        create_session(cls.old, **cls.target)
        cls.source = cls.base / 'stock.ipsw'
        cls.manifest = plistlib.dumps(dict(ProductVersion='10.3.4', ProductBuildVersion='14G61',
            SupportedProductTypes=['iPhone5,4'], BuildIdentities=[dict(Info=dict(DeviceClass='n49ap',
            RestoreBehavior='Erase'), Manifest={key: {'Info': {'Path': key + '.bin'}} for key in
            ('OS', 'iBSS', 'iBEC', 'RestoreRamDisk', 'KernelCache', 'iBoot')})]))
        with zipfile.ZipFile(cls.source, 'w') as archive:
            archive.writestr('BuildManifest.plist', cls.manifest)
        image = cls.old / 'image'
        image.mkdir()
        for name in ('BuildManifest.plist', 'BuildIdentity.plist', 'iBSS.restore.img3', 'iBSS.restore.patched', 'iBEC.jumpstart.img3'):
            (image / name).write_bytes(name.encode())
        (image / 'BuildManifest.plist').write_bytes(cls.manifest)
        output = cls.old / 'custom.ipsw'
        output.write_bytes(b'prepared fixture')
        info = dict(cls.target, phase='image-prepared', recipe=IMAGE_RECIPE, output=str(output),
                    output_sha256=digest(output), source_sha256=digest(cls.source),
                    stage_sha256=digest(cls.old / 'stage.tar'), jumpstart_ibec_sha256=digest(image / 'iBEC.jumpstart.img3'),
                    boot_artifacts={n: digest(image / n) for n in ('iBSS.restore.img3', 'iBSS.restore.patched', 'iBEC.jumpstart.img3')})
        write_json(image / 'preparation.json', info)
        Session(cls.old).register_image(image / 'preparation.json')

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def test_compatible_image_reuses_bytes_in_separate_attempt_preserving_original(self):
        before = (self.old / 'session.json').read_bytes()
        new = self.base / '12345-new'
        clone_attempt(self.old, new, self.source, ROOT / 'bin/macos', self.target)
        s = Session(new)
        self.assertEqual(s.data['phase'], 'image-ready')
        self.assertEqual(s.data['session'], Session(self.old).data['session'])
        self.assertEqual((new / 'custom.ipsw').read_bytes(), (self.old / 'custom.ipsw').read_bytes())
        self.assertEqual((self.old / 'session.json').read_bytes(), before)
        self.assertFalse((new / 'restore.log').exists())
        s.verify_boot_artifacts()

    def test_reuse_and_pre_restore_checks_hash_image_only_once(self):
        import session
        new = self.base / '12345-one-verification'
        with patch.object(session, 'digest', wraps=session.digest) as hashed:
            clone_attempt(self.old, new, self.source, ROOT / 'bin/macos', self.target)
            Session(new).verify_image()
            Session(new).verify_image()
        image_reads = [c for c in hashed.call_args_list if Path(c.args[0]).name == 'custom.ipsw']
        self.assertEqual(len(image_reads), 1)

    def test_changed_file_cannot_reuse_checksum_receipt(self):
        new = self.base / '12345-changed'
        clone_attempt(self.old, new, self.source, ROOT / 'bin/macos', self.target)
        image = new / 'custom.ipsw'
        original = image.read_bytes()
        stat = image.stat()
        try:
            image.write_bytes(b'X' * len(original))
            os.utime(image, ns=(stat.st_atime_ns, stat.st_mtime_ns))
            with self.assertRaisesRegex(ImageError, 'checksum mismatch'):
                Session(new).verify_image()
        finally:
            image.write_bytes(original)

    def test_candidates_do_not_hash_entire_stock_ipsw(self):
        import reuse
        with patch.object(reuse, 'digest', wraps=reuse.digest) as hashed:
            self.assertIn(self.old, candidates(self.base, self.target, self.source))
        self.assertFalse(any(Path(c.args[0]) == self.source for c in hashed.call_args_list))

    def test_old_recipe_is_rejected_before_clone_or_device_work(self):
        # A previously valid image must not bypass the new explicit-zero writer.
        with patch('reuse.IMAGE_RECIPE', IMAGE_RECIPE + 1):
            self.assertFalse(compatible(Session(self.old), self.target, self.manifest))
            new = self.base / 'old-recipe-rejected'
            with self.assertRaisesRegex(ImageError, 'not compatible'):
                clone_attempt(self.old, new, self.source, ROOT / 'bin/macos', self.target)
            self.assertFalse(new.exists())

    def test_wrong_device_source_or_phase_is_not_reusable(self):
        s = Session(self.old)
        for target in (dict(self.target, ecid='999'), dict(self.target, board='n48ap'),
                       dict(self.target, product='iPhone5,2', board='n42ap'),
                       dict(self.target, product='iPad3,4', board='p101ap')):
            self.assertFalse(compatible(s, target, self.manifest))
        self.assertFalse(compatible(s, self.target, b'wrong-manifest'))
        for phase in ('restore-running', 'awaiting-jumpstart', 'installing', 'complete'):
            s.data['phase'] = phase
            self.assertFalse(compatible(s, self.target, self.manifest))

    def test_corrupted_image_rejected_without_new_attempt(self):
        image = self.old / 'custom.ipsw'
        before = image.read_bytes()
        try:
            image.write_bytes(b'corrupted')
            with self.assertRaisesRegex(ImageError, 'checksum mismatch'):
                clone_attempt(self.old, self.base / 'bad-attempt', self.source, ROOT / 'bin/macos', self.target)
            self.assertFalse((self.base / 'bad-attempt').exists())
        finally:
            image.write_bytes(before)

    def test_current_stage_matches_but_changed_installer_is_rejected(self):
        from unittest.mock import patch
        import reuse
        s = Session(self.old)
        verify_stage(s)
        original = reuse.restore_files
        def changed(*args):
            files = original(*args)
            files['Applications/LIKTools.app/runtime.tar'] = (b'changed', 0o644)
            return files
        with patch.object(reuse, 'restore_files', changed):
            with self.assertRaisesRegex(ImageError, 'different installer files'):
                verify_stage(s)
