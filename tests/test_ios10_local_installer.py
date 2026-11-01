"""Native runtime tests: journal transitions, boot proof, child failures and AFC export."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]

@unittest.skipUnless(sys.platform == 'darwin' and shutil.which('xcrun'), 'Native runtime checks require macOS CLT')
class LocalInstallerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory(prefix='lik-local-')
        cls.folder = Path(cls.temp.name)
        source = ROOT / 'resources/ios10/socket-system'
        main = cls.folder / 'main.m'
        main.write_text(r'''#import "Diagnostics.h"
#import "Installer.h"
int main(int argc,char **argv) { @autoreleasepool {
    NSString *action=[NSString stringWithUTF8String:argv[1]];
    NSDictionary *r;
    if([action isEqual:@"phase"]) {
        NSString *next=LIKNextInstallStep([NSString stringWithUTF8String:argv[2]]);
        r=@{@"next":next ?: @"rejected"};
    } else if([action isEqual:@"proof"]) {
        NSMutableDictionary *w=[@{@"state":@"awaiting-ordinary-boot",@"persistent_setup_verified":@YES,@"pre_reboot_boot":@"old"} mutableCopy];
        NSMutableDictionary *s=[@{@"euid":@0,@"boot_arguments_readable":@YES,@"jumpstart_marker_present":@NO,@"kernel_task_access":@{@"success":@YES}} mutableCopy];
        NSString *boot=@"new";BOOL springboard=YES;NSString *which=[NSString stringWithUTF8String:argv[2]];
        if([which isEqual:@"same-boot"])boot=@"old";
        if([which isEqual:@"missing-boot"])boot=nil;
        if([which isEqual:@"unarmed"])[w removeObjectForKey:@"pre_reboot_boot"];
        if([which isEqual:@"unverified"])w[@"persistent_setup_verified"]=@NO;
        if([which isEqual:@"still-installing"])w[@"state"]=@"installing";
        if([which isEqual:@"unknown-args"])s[@"boot_arguments_readable"]=@NO;
        if([which isEqual:@"temporary-boot"])s[@"jumpstart_marker_present"]=@YES;
        if([which isEqual:@"mobile"])s[@"euid"]=@501;
        if([which isEqual:@"no-kernel-access"])s[@"kernel_task_access"]=@{@"success":@NO};
        if([which isEqual:@"no-home-screen"])springboard=NO;
        r=@{@"verified":@(LIKOrdinaryBootReady(w,boot,s,springboard))};
    } else if([action isEqual:@"export"]) {
        NSError *error=nil;NSString *path=LIKExportReport(@"App report: root helper unavailable\nPersistent diagnostics are still exportable.\n",&error);
        r=path?@{@"path":path}:@{@"error":error.localizedDescription};
    } else {
        NSString *log=[NSString stringWithUTF8String:argv[2]];
        NSString *command=[action isEqual:@"timeout"]?@"echo before-timeout; sleep 30":@"echo visible-log; echo failure-detail >&2; exit 23";
        r=LIKRunLogged(@"/bin/sh",@[@"-c",command],[action isEqual:@"timeout"]?0.3:5,log);
    }
    NSData *d=[NSJSONSerialization dataWithJSONObject:r options:0 error:nil];fwrite(d.bytes,1,d.length,stdout);return 0;
} }
''')
        stub=cls.folder/'socket-stub.m'
        stub.write_text('#import "SocketCore.h"\nNSString *SocketBundleFile(NSString *n){return nil;}\nNSDictionary *SocketAction(NSString *a){return @{};}\n')
        cls.binary=cls.folder/'runtime'
        subprocess.run(['xcrun','clang','-fobjc-arc','-fblocks','-I',str(source),
                        '-DLIK_EXPORT_DIR=@"'+str(cls.folder/'Media/Downloads/Legacy-iOS-Kit/Logs')+'"',
                        str(source/'Diagnostics.m'),str(source/'Installer.m'),str(stub),str(main),'-framework','Foundation','-o',str(cls.binary)],check=True,capture_output=True)

    @classmethod
    def tearDownClass(cls): cls.temp.cleanup()

    def run_native(self,*args):
        return json.loads(subprocess.check_output([str(self.binary),*args],timeout=10))

    def test_only_completed_steps_are_resumable(self):
        for phase,next_step in [('new','bootstrap'),('needs-settings','settings'),('settings-ready','untether'),('untether-installed','verify')]:
            self.assertEqual(self.run_native('phase',phase)['next'],next_step)
        for phase in ('bootstrap-running','bootstrap-failed','untether-running','untether-failed','incomplete-journal','unknown',''):
            self.assertEqual(self.run_native('phase',phase)['next'],'rejected')

    def test_boot_proof_requires_new_ordinary_root_boot_and_home_screen(self):
        self.assertTrue(self.run_native('proof','complete')['verified'])
        for condition in ('same-boot','missing-boot','unarmed','unverified','still-installing','unknown-args','temporary-boot','mobile','no-kernel-access','no-home-screen'):
            self.assertFalse(self.run_native('proof',condition)['verified'],condition)

    def test_worker_logs_real_exit_and_timeout_without_reporting_success(self):
        log=self.folder/'worker.log'
        result=self.run_native('failed',str(log))
        self.assertEqual(result['exit_code'],23)
        self.assertFalse(result['timed_out'])
        self.assertIn('visible-log',log.read_text())
        self.assertIn('failure-detail',result['tail'])
        result=self.run_native('timeout',str(log))
        self.assertTrue(result['timed_out'])
        self.assertNotEqual(result['exit_code'],0)
        self.assertIn('before-timeout',result['tail'])

    def test_export_succeeds_without_helper_and_uses_normal_media_path(self):
        result=self.run_native('export')
        self.assertTrue(result['path'].startswith('/Downloads/Legacy-iOS-Kit/Logs/iOS10-'))
        path=self.folder/'Media'/result['path'].lstrip('/')
        self.assertIn('root helper unavailable',path.read_text())
        second=self.run_native('export')
        self.assertNotEqual(second['path'],result['path'])
        self.assertTrue(path.is_file())
