// Derived from Socket 1.3, staturnzz, MIT; see Socket-LICENSE and source.json.
// The jump-start supplies kernel patches. Socket's own credential acquisition
// remains necessary because SpringBoard starts this app as mobile.
#import "SocketCore.h"
#import "Diagnostics.h"
#import "Installer.h"
#include "upstream/exploit/oob_entry.h"
#include "upstream/exploit/memory.h"
#include "upstream/exploit/util.h"
#import <CommonCrypto/CommonDigest.h>
#include <mach-o/dyld.h>
#include <sys/mount.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <errno.h>

void status(const char *message) {
    NSString *text=[NSString stringWithUTF8String:message ?: ""] ?: @"Non-UTF8 Socket message";
    [[NSNotificationCenter defaultCenter] postNotificationName:@"SocketStatus" object:nil userInfo:@{@"message":text}];
}
NSString *SocketBundleFile(NSString *name) {
    char path[4096]={0};uint32_t size=sizeof(path);
    if(_NSGetExecutablePath(path,&size))return nil;
    return [[[NSString stringWithUTF8String:path] stringByDeletingLastPathComponent] stringByAppendingPathComponent:name];
}
int set_permissions(void) {
    for (uint32_t i = 0; i < 20; i++) {
        uint32_t kern_cred = kread32(kinfo->kern_proc_addr + koffsetof(proc, ucred));
        uint32_t ucred_pa = kvtophys(kread32(kinfo->self_proc_addr + koffsetof(proc, ucred)));
        physwrite32(ucred_pa + 0xc, 0);
        physwrite32(ucred_pa + 0x10, 0);
        physwrite32(ucred_pa + 0x14, 0);
        physwrite32(ucred_pa + 0x1c, 0);
        physwrite32(ucred_pa + 0x5c, 0);
        usleep(10000);
        
        setuid(0);
        setgid(0);
        seteuid(0);
        setegid(0);
        setruid(0);
        setrgid(0);
        
        kwrite32(kinfo->self_proc_addr + koffsetof(proc, ucred), kern_cred);
        usleep(100000);
        sync();
        
        kwrite32(kinfo->self_proc_addr + koffsetof(proc, ucred), kern_cred);
        usleep(100000);
        sync();
        
        setuid(0);
        setgid(0);
        seteuid(0);
        setegid(0);
        setruid(0);
        setrgid(0);
        if (getuid() == 0) return 0;
    }
    return (getuid() == 0) ? 0 : -1;
}

int remount_rootfs(void) {
    if (access("/", R_OK|W_OK) == 0) return 0;
    struct statfs st = {0};
    statfs("/", &st);

    char *dev = strdup("/dev/disk0s1s1");
    int rv = mount(st.f_fstypename, "/", MNT_UPDATE, &dev);
    free(dev);

    if (rv != 0) return -1;
    return access("/", R_OK|W_OK);
}


static BOOL OK(NSDictionary *r){return r[@"exit_code"] && [r[@"exit_code"] intValue]==0 && ![r[@"timed_out"] boolValue];}
static NSString *SHA(NSData *data){if(!data)return nil;unsigned char b[CC_SHA256_DIGEST_LENGTH];CC_SHA256(data.bytes,(CC_LONG)data.length,b);NSMutableString *s=[NSMutableString string];for(int i=0;i<CC_SHA256_DIGEST_LENGTH;i++)[s appendFormat:@"%02x",b[i]];return s;}
static NSString *IdentityCheck(void) {
    NSString *identity=[NSString stringWithContentsOfFile:SocketBundleFile(@"identity") encoding:NSUTF8StringEncoding error:nil];
    NSArray *parts=[identity componentsSeparatedByString:@"\n"];if(parts.count!=7)return @"The app's restore identity is missing or malformed";
    NSDictionary *snapshot=LIKSnapshot();
    if(![parts[1] isEqual:snapshot[@"device"]] || [parts[2] caseInsensitiveCompare:snapshot[@"board"]]!=NSOrderedSame || ![parts[4] isEqual:snapshot[@"build"]])return @"The app does not match this device and firmware";
    return nil;
}
NSString *SocketEnsureRoot(void) {
    NSString *error=IdentityCheck();if(error)return error;
    if(getuid()==0 && geteuid()==0)return nil;
    NSDictionary *before=LIKSnapshot();
    // On an ordinary boot, credential acquisition is only for maintenance of an
    // existing installation. It never applies kernel jailbreak patches.
    if(![before[@"jumpstart_marker_present"] boolValue] && access("/var/root/procyon",F_OK)!=0 && access("/.installed_socket",F_OK)!=0)
        return @"Enter DFU and use Jumpstart iOS 10 Untethered Jailbreak before installation";
    status("Acquiring app privileges using Socket's credential routine.\n");
    if(kinfo==NULL && run_oob_entry(false)!=0)return @"Socket could not obtain its memory-access primitive; no packages were installed";
    if(set_permissions()!=0 || getuid()!=0 || geteuid()!=0)return @"Socket could not obtain root; no packages were installed";
    status("Root access confirmed. The jump-start kernel patches will not be applied again.\n");
    return nil;
}
NSString *SocketPrepareRuntime(void) {
    NSString *error=SocketEnsureRoot();if(error)return error;
    if(![LIKSnapshot()[@"jumpstart_marker_present"] boolValue] && access("/usr/local/share/lik-ios10/identity",F_OK)!=0)return @"The temporary jump-start is required before the first installation";
    NSData *expected=[NSData dataWithContentsOfFile:SocketBundleFile(@"identity")];
    NSString *target=[LIK_DIR stringByAppendingPathComponent:@"identity"];
    if(access(target.fileSystemRepresentation,F_OK)==0) {
        if(![expected isEqual:[NSData dataWithContentsOfFile:target]])return @"Existing installer files belong to another restore";
        return nil; // The installer verifies every staged checksum before use.
    }
    for(NSString *path in @[LIK_DIR,@"/usr/lik",@"/bin/sh"]) {
        struct stat st;if(lstat(path.fileSystemRepresentation,&st)==0)return @"Unexpected existing installer or shell files; export logs before recovery";
    }
    NSData *archive=[NSData dataWithContentsOfFile:SocketBundleFile(@"runtime.tar")];
    NSString *expectedHash=[[NSString stringWithContentsOfFile:SocketBundleFile(@"runtime.sha256") encoding:NSUTF8StringEncoding error:nil] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if(!archive || ![SHA(archive) isEqual:expectedHash])return @"Bundled runtime archive checksum failed";
    if(remount_rootfs()!=0)return @"Socket could not remount the system filesystem";
    status("Preparing the bundled on-device runtime. No computer connection is needed.\n");
    NSDictionary *r=LIKRunTimed(SocketBundleFile(@"tar"),@[@"-xvf",SocketBundleFile(@"runtime.tar"),@"-C",@"/",@"--preserve-permissions",@"--no-overwrite-dir"],120);
    if(!OK(r) || ![expected isEqual:[NSData dataWithContentsOfFile:target]])return [@"Runtime extraction failed: " stringByAppendingString:r.description];
    return LIKPrepareJournal();
}
// Socket's first-install order: tar/launchctl, bootstrap, Zebra, firmware
// registration. Preference edits and Procyon are separate journaled phases.
int SocketInstallBootstrap(void) {
    if(getuid()!=0 || geteuid()!=0)return 1;
    if(![LIKSnapshot()[@"jumpstart_marker_present"] boolValue])return 2;
    for(NSString *name in @[@"tar",@"launchctl"]) {
        NSString *src=[LIK_DIR stringByAppendingPathComponent:name],*dst=[@"/bin" stringByAppendingPathComponent:name];
        NSData *data=[NSData dataWithContentsOfFile:src];
        if(!data || ![data writeToFile:dst atomically:YES] || chown(dst.fileSystemRepresentation,0,0) || chmod(dst.fileSystemRepresentation,0755))return 3;
    }
    status("Installing Socket's bootstrap…\n");
    NSDictionary *tar=LIKRunTimed(@"/bin/tar",@[@"-xvf",[LIK_DIR stringByAppendingPathComponent:@"bootstrap.tar"],@"-C",@"/",@"--preserve-permissions",@"--no-overwrite-dir"],1200);
    fprintf(stderr,"%s\n",[tar.description UTF8String]);if(!OK(tar))return 4;
    status("Installing Zebra…\n");
    NSDictionary *zebra=LIKRunTimed(@"/usr/bin/dpkg",@[@"--force-all",@"-i",[LIK_DIR stringByAppendingPathComponent:@"zebra.deb"]],600);
    fprintf(stderr,"%s\n",[zebra.description UTF8String]);if(!OK(zebra))return 5;
    NSString *db=[NSString stringWithContentsOfFile:@"/var/lib/dpkg/status" encoding:NSUTF8StringEncoding error:nil];
    if([db rangeOfString:@"Name: iOS Firmware"].location==NSNotFound || !db) {
        NSDictionary *firmware=LIKRunTimed(@"/bin/sh",@[@"/usr/libexec/cydia/firmware.sh"],120);
        fprintf(stderr,"%s\n",[firmware.description UTF8String]);if(!OK(firmware))return 6;
    }
    return 0;
}
int SocketConfigureUntether(void) {
    if(getuid()!=0 || geteuid()!=0)return 1;
    status("Installing Procyon and generating its boot stages…\n");
    NSDictionary *r=LIKRunTimed(@"/usr/bin/dpkg",@[@"--force-all",@"--configure",@"com.staturnz.procyon"],1800);
    fprintf(stderr,"%s\n",[r.description UTF8String]);return OK(r)?0:1;
}
NSDictionary *SocketAction(NSString *action) {
    NSMutableDictionary *result=[NSMutableDictionary dictionaryWithDictionary:@{@"action":action,@"engine":@"Socket 1.3 — Legacy iOS Kit adaptation"}];
    BOOL privileged=![@[@"status",@"export-logs"] containsObject:action];
    if([action isEqual:@"status"] && access("/.installed_socket",F_OK)==0)privileged=YES;
    NSString *error=privileged?SocketEnsureRoot():nil;
    if(!error && privileged && ![@[@"checks",@"reboot-and-verify"] containsObject:action])error=SocketPrepareRuntime();
    if(error)result[@"error"]=error;
    if(!error && [action isEqual:@"install"]) {
        result[@"ssh_check"]=LIKSSHAction(@"start-ssh");
        [result addEntriesFromDictionary:LIKStartInstall()];
    } else if(!error && [action isEqual:@"reboot-and-verify"])[result addEntriesFromDictionary:LIKStartReboot()];
    else if(!error && [@[@"restart-ssh",@"fix-ssh",@"reinstall-ssh"] containsObject:action])result[@"ssh_action"]=LIKSSHAction(action);
    else if(!error && [action isEqual:@"checks"] && access("/usr/local/share/lik-ios10/identity",F_OK)==0)result[@"ssh_action"]=LIKSSHAction(@"check-ssh");
    if(geteuid()==0 && access("/usr/local/share/lik-ios10/identity",F_OK)==0)LIKVerifyOrdinaryBoot();
    result[@"root_access"]=@(geteuid()==0 && getuid()==0);result[@"snapshot"]=LIKSnapshot();
    result[@"workflow"]=LIKWorkflow();result[@"installer_logs"]=LIKInstallerLogs();
    if([action isEqual:@"export-logs"]) {
        NSMutableDictionary *logs=[NSMutableDictionary dictionary];NSString *j=LIKJournal();
        if(j)for(NSString *name in @[@"bootstrap.log",@"untether.log",@"verification.log",@"ondevice-install.log",@"ondevice-reboot.log"])logs[name]=LIKReadExportLog([j stringByAppendingPathComponent:name]);
        logs[@"ssh.log"]=LIKReadExportLog(@"/var/log/lik-ios10-transport.log");result[@"installer_logs"]=logs;
    }
    if(!result[@"ssh_check"])result[@"ssh_check"]=LIKSSHLastResult();
    return result;
}
