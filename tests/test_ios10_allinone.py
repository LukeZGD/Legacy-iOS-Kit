import hashlib, io, json, os, plistlib, re, shutil, subprocess, sys, tarfile, tempfile, unittest, importlib.util
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'resources/ios10'))
from allinone_stage import compose, write_tar, name
from prepare import IMAGE_RECIPE, validate_stage, digest, write_json
from macho import ImageError
from restore_audit import audit
from session import Session
from reuse import verify_stage

class AllInOneAssetsTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.info=dict(schema=1,session='11111111-1111-1111-1111-111111111111',product='iPhone5,4',board='n49ap',version='10.3.4',build='14G61',ecid='12345')
        cls.files,cls.manifest=compose(cls.info)

    def test_system_data_split_and_package_configuration(self):
        plan=plistlib.loads(self.files['usr/local/share/lik-aio/plan.plist'][1])
        self.assertFalse(any(n.startswith(('private/var/','var/','Applications/LIKTools.app')) for n in self.files))
        paths={e['path']:e for e in plan['data']}
        self.assertNotIn('lib/dpkg/status',paths)
        self.assertEqual([e['path'] for e in plan['final_data']],['lib/dpkg/status'])
        self.assertIn('lib/dpkg/info/com.staturnz.procyon.postinst',paths)
        self.assertEqual(self.files['Applications/Zebra.app/supersling'][0].mode,0o6755)
        self.assertEqual(self.files['Applications/Zebra.app/supersling'][0].uid,0)
        z=plistlib.loads(self.files['Applications/Zebra.app/Info.plist'][1])
        self.assertIn('sileo',z['CFBundleURLTypes'][0]['CFBundleURLSchemes'])
        for e in plan['data']+plan['final_data']:
            if e['kind']=='file':
                self.assertEqual(hashlib.sha256(self.files['usr/local/share/lik-aio/data/'+e['blob']][1]).hexdigest(),e['sha256'])
        self.assertEqual(paths['mobile/Library/Application Support/xyz.willy.Zebra']['uid'],501)

    def test_each_variant_gets_its_own_target_plan(self):
        for product,board in (('iPhone5,1','n41ap'),('iPhone5,2','n42ap'),
                              ('iPhone5,3','n48ap'),('iPhone5,4','n49ap'),
                              ('iPad3,4','p101ap'),('iPad3,5','p102ap'),('iPad3,6','p103ap')):
            with self.subTest(product=product):
                files,_=compose(dict(self.info,product=product,board=board))
                plan=plistlib.loads(files['usr/local/share/lik-aio/plan.plist'][1])
                self.assertEqual((plan['product'],plan['board']),(product,board))
                status=plan['final_data'][0]
                self.assertIn(b'Package: firmware\n',files['usr/local/share/lik-aio/data/'+status['blob']][1])
                self.assertNotIn('Library/LaunchDaemons/org.legacyioskit.ios10.metadata.plist',files)

    def test_archive_has_no_unterminated_100_byte_names(self):
        with tempfile.TemporaryDirectory() as tmp:
            p=Path(tmp)/'stage.tar';write_tar(p,self.files);validate_stage(p)
            raw=p.read_bytes();offset=0;long_name=False
            while raw[offset:offset+512].strip(b'\0'):
                header=raw[offset:offset+512]
                if not long_name:self.assertIn(b'\0',header[:100])
                long_name=header[156:157]==b'L'
                size=int(header[124:136].rstrip(b'\0 ') or b'0',8)
                offset+=512+((size+511)//512)*512
            with tarfile.open(p) as archive:
                entries={name(m.name):m for m in archive}
                long='Applications/Zebra.app/Base.lproj/Main.storyboardc/ZBChangesTableViewController.nib/objects-9.1+.nib'
                self.assertEqual(archive.extractfile(entries[long]).read(),self.files[long][1])

    def test_reuse_rejects_changed_payload_and_accepts_original(self):
        with tempfile.TemporaryDirectory() as tmp:
            p=Path(tmp);p.chmod(0o700);write_tar(p/'stage.tar',self.files)
            write_json(p/'session.json',dict(self.info,installer='restore-allinone',phase='staged'))
            verify_stage(Session(p))
            changed=dict(self.files);m,_=changed['bin/launchctl'];changed['bin/launchctl']=(m,b'changed')
            write_tar(p/'stage.tar',changed)
            with self.assertRaisesRegex(Exception,'contents changed'):verify_stage(Session(p))

    def test_every_boot_patch_lookup_has_a_generated_address(self):
        spec=importlib.util.spec_from_file_location('aio_builder',ROOT/'resources/ios10/allinone/build.py')
        module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
        with tempfile.TemporaryDirectory() as tmp:
            source=module.adapt(Path(tmp))
            descriptor=(source/'src/stage3.c').read_text()
        js=''.join(p.read_text() for p in (ROOT/'resources/ios10/allinone/upstream/untether/src').glob('*.js'))
        required=set(re.findall(r'info\.patches\.([A-Za-z0-9_]+)',js))
        keys=set(re.findall(r'\b([A-Za-z0-9_]+): 0x%x',descriptor))
        self.assertFalse(required-keys,required-keys)
        self.assertNotIn('pid_cvm_map_protectheck:',descriptor)

    def test_success_requires_late_trigger_then_completion(self):
        start='[LIK-AIO] FINAL_MOUNTED_STAGE:';done='[LIK-AIO] INSTALLATION_COMPLETE:';fail='[LIK-AIO] INSTALLATION_FAILED'
        self.assertTrue(audit(start+'\r\n'+done)['installation_verified'])
        for log in ('',done,done+start,start+fail,start+done+fail):self.assertFalse(audit(log)['installation_verified'])


class AllInOneBootValidationTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory()
        self.root=Path(self.tmp.name)
        self.root.chmod(0o700)
        self.boot={}
        for name in ('iBSS.restore.img3','iBSS.restore.patched'):
            p=self.root/name;p.write_bytes(name.encode());self.boot[name]=digest(p)
        write_json(self.root/'session.json',dict(schema=1,
            session='11111111-1111-1111-1111-111111111111',product='iPhone5,4',
            board='n49ap',version='10.3.4',build='14G61',ecid='12345',
            installer='restore-allinone',phase='image-ready'))
        self.session=Session(self.root)

    def tearDown(self):
        self.tmp.cleanup()

    def preparation(self,recipe,installer='restore-allinone'):
        p=self.root/'preparation.json'
        write_json(p,dict(recipe=recipe,installer=installer,boot_artifacts=self.boot))
        self.session.data.update(preparation=str(p),preparation_sha256=digest(p))

    def test_current_builder_recipe_passes_without_jumpstart_artifacts(self):
        self.preparation(IMAGE_RECIPE)
        self.session.verify_boot_artifacts()
        self.assertFalse((self.root/'iBEC.jumpstart.img3').exists())

    def test_other_recipes_and_installer_types_are_rejected(self):
        for recipe,installer in ((7,'restore-allinone'),(8,'restore-allinone'),(9,'restore-allinone'),(10,'restore-allinone'),
                (IMAGE_RECIPE+1,'restore-allinone'),(IMAGE_RECIPE,'socket-app')):
            with self.subTest(recipe=recipe,installer=installer):
                self.preparation(recipe,installer)
                with self.assertRaisesRegex(ImageError,'Expected an all-in-one restore image'):
                    self.session.verify_boot_artifacts()

    def test_changed_loader_is_still_rejected(self):
        self.preparation(IMAGE_RECIPE)
        (self.root/'iBSS.restore.img3').write_bytes(b'changed')
        with self.assertRaisesRegex(ImageError,'Boot artifact checksum mismatch'):
            self.session.verify_boot_artifacts()

class NativeRestoreHookTests(unittest.TestCase):
    def test_forwards_nvram_and_only_finalizes_exact_late_operation(self):
        cc=shutil.which('clang') or shutil.which('cc')
        if not cc:self.skipTest('Host C compiler unavailable')
        with tempfile.TemporaryDirectory() as tmp:
            p=Path(tmp);stock=p/'stock';final=p/'final'
            stock.write_text('#!/bin/sh\nprintf "nvram:%s\\n" "$*" >> "$TRACE"\nexit "${STOCK_RESULT:-0}"\n')
            final.write_text('#!/bin/sh\nprintf "finalize\\n" >> "$TRACE"\nexit "${INSTALL_RESULT:-0}"\n')
            stock.chmod(0o755);final.chmod(0o755)
            source=(ROOT/'resources/ios10/allinone/nvram.c').read_text().replace('/usr/sbin/nvram.stock',str(stock)).replace('/usr/local/bin/lik-restore-finalize',str(final))
            (p/'hook.c').write_text(source);subprocess.run([cc,str(p/'hook.c'),'-o',str(p/'hook')],check=True)
            def run(args,**env):
                trace=p/'trace';trace.write_text('')
                r=subprocess.run([str(p/'hook'),*args],env=dict(os.environ,TRACE=str(trace),**env),stdout=subprocess.PIPE,stderr=subprocess.PIPE)
                return r.returncode,trace.read_text().splitlines()
            for args in (['boot-args='],['auto-boot=true'],['bootdelay=1'],['-p'],['bootdelay=0','extra']):
                code,lines=run(args);self.assertEqual(code,0);self.assertEqual(len(lines),1)
            self.assertEqual(run(['bootdelay=0']), (0,['nvram:bootdelay=0','finalize']))
            self.assertEqual(run(['bootdelay=0'],INSTALL_RESULT='9'),(9,['nvram:bootdelay=0','finalize','nvram:auto-boot=false']))
            self.assertEqual(run(['bootdelay=0'],STOCK_RESULT='7'),(7,['nvram:bootdelay=0']))
