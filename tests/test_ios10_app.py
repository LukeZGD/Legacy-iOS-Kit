"""Check delivered ARM32 app/helper and execute their native transport client."""
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import socket
import struct
import subprocess
import sys
import tarfile
import tempfile
import threading
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'resources/ios10'))
import stage
from macho import commands, check_or_update_hashes

class AppArchiveTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.files,_,_=stage.runtime_files(ROOT/'resources')

    def test_native_binaries_are_signed_armv7_ios10_with_only_stock_dependencies(self):
        for name in ('Applications/LIKTools.app/LIKTools',):
            with self.subTest(name=name):
                data,mode=self.files[name]
                self.assertEqual(struct.unpack_from('<III',data),(0xfeedface,12,9))
                self.assertEqual(mode,0o755)
                found_version=False
                for cmd,pos,size in commands(data):
                    if cmd==0x25: # LC_VERSION_MIN_IPHONEOS
                        self.assertEqual(struct.unpack_from('<I',data,pos+8)[0],10<<16)
                        found_version=True
                    if cmd in (0xc,0x80000018):
                        offset=struct.unpack_from('<I',data,pos+8)[0]
                        dep=data[pos+offset:pos+size].split(b'\0')[0].decode()
                        self.assertTrue(dep.startswith(('/usr/lib/','/System/Library/Frameworks/')),dep)
                        self.assertNotIn('/usr/lik',dep)
                self.assertTrue(found_version)
                check_or_update_hashes(data)

    def test_sources_match_packaged_build_and_app_visibility_metadata(self):
        metadata=json.loads((ROOT/'resources/ios10/assets/socket-system-build.json').read_text())
        for name,sha in metadata['source_sha256'].items():
            self.assertEqual(hashlib.sha256((ROOT/'resources/ios10/socket-system'/name).read_bytes()).hexdigest(),sha,name)
        info=plistlib.loads(self.files['Applications/LIKTools.app/Info.plist'][0])
        self.assertEqual(info['CFBundleExecutable'],'LIKTools')
        self.assertEqual(info['UIDeviceFamily'],[1,2])
        self.assertEqual(info['MinimumOSVersion'],'10.0')
        self.assertEqual(info['CFBundleDisplayName'],'Socket (Kit)')
        self.assertNotIn('usr/local/share/lik-ios10/diagnostic-helper',self.files)
        self.assertFalse(any(n.startswith('System/Library/LaunchDaemons/') for n in self.files))

    def test_repair_manifest_reconstructs_exact_runtime_and_session_credentials(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder=Path(tmp);(folder/'host_rsa').write_bytes(b'FAKE-SERVER-KEY')
            identity=dict(schema=1,session='01234567-0123-4567-89ab-0123456789ab',product='iPhone5,4',board='n49ap',version='10.3.4',build='14G61',ecid='12345')
            files=stage.session_files(folder,identity,dict(self.files),'ssh-rsa FAKE-PUBLIC')
            repair=plistlib.loads(files['usr/local/share/lik-ios10/ssh-repair.plist'][0])
            self.assertLessEqual(len(repair),64)
            self.assertEqual(set('/'+n for n in files if n.startswith('usr/lik/'))-set(repair),set())
            for destination,entry in repair.items():
                data,mode=files[destination.lstrip('/')]
                backup,backup_mode=files[entry['source'].lstrip('/')]
                self.assertEqual(backup,data)
                self.assertEqual(backup_mode,0o600)
                self.assertEqual(mode,entry['mode'])
                self.assertEqual(entry['sha256'],hashlib.sha256(backup).hexdigest())
            self.assertNotIn('/usr/bin/procyon',repair)
            self.assertFalse(any('client_rsa' in path for path in files))
            sums=files['usr/local/share/lik-ios10/SHA256SUMS'][0].decode()
            self.assertIn('/Applications/LIKTools.app/LIKTools',sums)

@unittest.skipUnless(sys.platform=='darwin' and shutil.which('xcrun'),'Native client test requires macOS CLT')
class NativeDiagnosticClientTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp=tempfile.TemporaryDirectory(prefix='lik-app-',dir='/tmp')
        cls.folder=Path(cls.temp.name)
        cls.address=str(cls.folder/'helper.sock')
        cls.main=cls.folder/'main.m'
        cls.main.write_text('''#import "Diagnostics.h"
int main(int argc,char **argv) { @autoreleasepool {
  NSDictionary *r;
  if(argc>1 && strcmp(argv[1],"snapshot")==0)r=LIKSnapshot();
  else if(argc>1 && strcmp(argv[1],"spawn")==0)r=LIKRun(@"/usr/bin/false",@[]);
  else r=LIKRequest(argc>1 ? [NSString stringWithUTF8String:argv[1]] : @"status");
  NSData *d=[NSJSONSerialization dataWithJSONObject:r options:0 error:nil];
  fwrite(d.bytes,1,d.length,stdout);return 0;
} }
''')
        source=ROOT/'resources/ios10/diagnostics'
        cls.binary=cls.folder/'client'
        subprocess.run(['xcrun','clang','-fobjc-arc','-fblocks','-I',str(source),'-DLIK_SOCKET="'+cls.address+'"',str(source/'Diagnostics.m'),str(cls.main),'-framework','Foundation','-o',str(cls.binary)],check=True,capture_output=True)

    @classmethod
    def tearDownClass(cls):cls.temp.cleanup()

    def client(self,action='status'):
        return json.loads(subprocess.check_output([str(self.binary),action],timeout=15))

    def exchange(self,reply):
        server=socket.socket(socket.AF_UNIX,socket.SOCK_STREAM)
        server.bind(self.address);server.listen(1)
        request=[];errors=[]
        def serve():
            try:
                conn,_=server.accept()
                with conn:
                    request.append(conn.recv(128))
                    try:conn.sendall(reply)
                    except BrokenPipeError:pass
            except Exception as exc:errors.append(exc)
        thread=threading.Thread(target=serve);thread.start()
        try:result=self.client()
        finally:
            thread.join(timeout=5);server.close();os.unlink(self.address)
        self.assertFalse(thread.is_alive())
        self.assertFalse(errors,errors)
        self.assertEqual(request,[b'status\n'])
        return result

    def test_status_reply_and_malformed_or_oversized_replies(self):
        self.assertEqual(self.exchange(b'{"snapshot":{"euid":0}}')['snapshot']['euid'],0)
        self.assertIn('error',self.exchange(b'not json'))
        self.assertIn('error',self.exchange(b'[]'))
        self.assertIn('size limit',self.exchange(b'x'*270000)['error'])

    def test_missing_helper_and_unknown_action_are_reported_without_crash(self):
        self.assertFalse(self.client()['root_helper_responded'])
        self.assertIn('Unknown',self.client('install-untether')['error'])

    def test_snapshot_and_child_failure_are_evidence_not_success(self):
        report=self.client('snapshot')
        self.assertEqual(report['euid'],os.geteuid())
        self.assertFalse(report['jumpstart_marker_present'])
        self.assertIn('installer_phase',report)
        self.assertEqual(self.client('spawn')['exit_code'],1)
