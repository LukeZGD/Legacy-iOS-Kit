#import "Diagnostics.h"
#import "Installer.h"
#import <CommonCrypto/CommonDigest.h>
#import <sys/stat.h>
#import <sys/file.h>
#import <fcntl.h>
#import <unistd.h>
#import <errno.h>
static BOOL LIKOK(NSDictionary *r){return r[@"exit_code"] && [r[@"exit_code"] intValue]==0 && ![r[@"timed_out"] boolValue];}
static NSString *LIKSHA(NSData *data) {
    unsigned char hash[CC_SHA256_DIGEST_LENGTH];CC_SHA256(data.bytes,(CC_LONG)data.length,hash);
    NSMutableString *text=[NSMutableString string];for(int i=0;i<CC_SHA256_DIGEST_LENGTH;i++)[text appendFormat:@"%02x",hash[i]];return text;
}
static NSString *LIKRepairFiles(BOOL force, NSUInteger *changed) {
    NSDictionary *manifest=[NSDictionary dictionaryWithContentsOfFile:[LIK_DIR stringByAppendingPathComponent:@"ssh-repair.plist"]];
    if(!manifest.count || manifest.count>64)return @"Repair manifest missing or invalid";
    NSSet *allowed=[NSSet setWithArray:@[@"sshd",@"ssh",@"ssh-keygen",@"bash",@"openssl",@"libcrypto.0.9.8.dylib",@"libssl.0.9.8.dylib",@"libreadline.6.0.dylib",@"libhistory.6.0.dylib",@"libncurses.5.dylib",@"tar",@"cat",@"mkdir",@"mv",@"cp",@"rm",@"ln",@"sleep",@"sync",@"chmod",@"chown",@"readlink",@"dd",@"sysctl",@"sw_vers",@"cmp"]];
    NSMutableDictionary *checked=[NSMutableDictionary dictionary];
    for(NSString *destination in manifest) {
        NSDictionary *entry=manifest[destination];NSString *source=entry[@"source"];
        BOOL runtime=[destination.stringByDeletingLastPathComponent isEqual:@"/usr/lik"] && [allowed containsObject:destination.lastPathComponent];
        BOOL config=[@[[LIK_DIR stringByAppendingPathComponent:@"sshd_config"],[LIK_DIR stringByAppendingPathComponent:@"host_rsa"],[LIK_DIR stringByAppendingPathComponent:@"authorized_keys"],[LIK_DIR stringByAppendingPathComponent:@"launchctl"],[LIK_DIR stringByAppendingPathComponent:@"transport.sh"],[LIK_DIR stringByAppendingPathComponent:@"common.sh"],LIK_SSH_PLIST] containsObject:destination];
        if((!runtime && !config) || ![source.stringByDeletingLastPathComponent isEqual:[LIK_DIR stringByAppendingPathComponent:@"ssh-repair"]])return @"Repair path outside fixed allowlist";
        int mode=[entry[@"mode"] intValue];if(mode!=0600 && mode!=0644 && mode!=0755)return @"Invalid repair permissions";
        struct stat st;if(lstat(source.fileSystemRepresentation,&st)||!S_ISREG(st.st_mode)||st.st_uid!=0||(st.st_mode&0022))return @"Repair source ownership/type check failed";
        NSData *data=[NSData dataWithContentsOfFile:source];if(!data || ![LIKSHA(data) isEqual:entry[@"sha256"]])return @"Repair source checksum failed";
        if(lstat(destination.stringByDeletingLastPathComponent.fileSystemRepresentation,&st)||!S_ISDIR(st.st_mode)||st.st_uid!=0||(st.st_mode&0022))return @"Repair destination parent check failed";
        if(lstat(destination.fileSystemRepresentation,&st)==0 && !S_ISREG(st.st_mode))return @"Repair refuses a symlink or non-file destination";
        NSData *current=[NSData dataWithContentsOfFile:destination];
        struct stat existing;BOOL permissions=lstat(destination.fileSystemRepresentation,&existing)==0 && existing.st_uid==0 && existing.st_gid==0 && (existing.st_mode&07777)==mode;
        if(force || !permissions || ![current isEqual:data])checked[destination]=data;
    }
    *changed=checked.count;
    if(!checked.count)return nil;
    NSDictionary *mount=LIKRun(@"/sbin/mount",@[@"-u",@"-w",@"/"]);
    if(!LIKOK(mount))return [@"System remount failed: " stringByAppendingString:mount.description];
    LIKRun([LIK_DIR stringByAppendingPathComponent:@"launchctl"],@[@"unload",LIK_SSH_PLIST]);
    for(NSString *destination in checked) {
        NSError *error=nil;
        if(![checked[destination] writeToFile:destination options:NSDataWritingAtomic error:&error])return error.localizedDescription;
        if(chown(destination.fileSystemRepresentation,0,0)||chmod(destination.fileSystemRepresentation,[manifest[destination][@"mode"] intValue]))return @"Repair ownership/permissions failed";
    }
    sync();return nil;
}

static NSDictionary *SelfTest(BOOL configure) {
    NSString *journal=LIKJournal();if(!journal)return @{@"error":@"Installer identity unavailable"};
    NSString *key=[journal stringByAppendingPathComponent:@"ssh-selftest"];
    NSString *known=[journal stringByAppendingPathComponent:@"ssh-known-hosts"];
    if(configure) {
        if(access(key.fileSystemRepresentation,F_OK)) {
            NSDictionary *generated=LIKRunTimed(@"/usr/lik/ssh-keygen",@[@"-q",@"-t",@"rsa",@"-b",@"2048",@"-N",@"",@"-f",key],60);
            if(!LIKOK(generated))return @{@"error":@"Could not create the phone's SSH self-test credential",@"keygen":generated};
        }
        NSDictionary *public=LIKRun(@"/usr/lik/ssh-keygen",@[@"-y",@"-f",key]);
        NSDictionary *host=LIKRun(@"/usr/lik/ssh-keygen",@[@"-y",@"-f",[LIK_DIR stringByAppendingPathComponent:@"host_rsa"]]);
        if(!LIKOK(public)||!LIKOK(host))return @{@"error":@"Could not derive the SSH public keys"};
        NSError *error=nil;
        NSString *pubfile=[key stringByAppendingString:@".pub"];
        if(![public[@"output"] writeToFile:pubfile atomically:YES encoding:NSUTF8StringEncoding error:&error] || ![[@"lik-ios10-local " stringByAppendingString:host[@"output"]] writeToFile:known atomically:YES encoding:NSUTF8StringEncoding error:&error])return @{@"error":error.localizedDescription ?: @"SSH self-test configuration failed"};
        chmod(key.fileSystemRepresentation,0600);chmod(pubfile.fileSystemRepresentation,0600);chmod(known.fileSystemRepresentation,0600);
    }
    if(access(key.fileSystemRepresentation,R_OK)||access(known.fileSystemRepresentation,R_OK))return @{@"error":@"SSH self-test configuration is missing. Fix SSH can restore it."};
    NSArray *args=@[@"-F",@"/dev/null",@"-T",@"-p",@"44",@"-i",key,@"-o",@"BatchMode=yes",@"-o",@"IdentitiesOnly=yes",@"-o",@"StrictHostKeyChecking=yes",@"-o",[@"UserKnownHostsFile=" stringByAppendingString:known],@"-o",@"GlobalKnownHostsFile=/dev/null",@"-o",@"HostKeyAlias=lik-ios10-local",@"-o",@"ConnectTimeout=5",@"root@127.0.0.1",@"info"];
    NSDictionary *r=LIKRunTimed(@"/usr/lik/ssh",args,12);
    NSString *identity=[NSString stringWithContentsOfFile:[LIK_DIR stringByAppendingPathComponent:@"identity"] encoding:NSUTF8StringEncoding error:nil];
    NSString *session=[[identity componentsSeparatedByString:@"\n"] firstObject];
    NSString *output=r[@"output"] ?: @"";
    BOOL authenticated=LIKOK(r) && [[output componentsSeparatedByString:@"\n"] containsObject:@"uid=0"] && [[output componentsSeparatedByString:@"\n"] containsObject:[@"session=" stringByAppendingString:session ?: @"INVALID"]];
    NSMutableDictionary *result=[r mutableCopy];result[@"authenticated"]=@(authenticated);
    if(!authenticated)result[@"error"]=@"Authenticated SSH identity check failed; see the command result";
    return result;
}
NSDictionary *LIKSSHLastResult(void) {
    NSString *j=LIKJournal();if(!j)return @{};
    return [NSDictionary dictionaryWithContentsOfFile:[j stringByAppendingPathComponent:@"ssh-check.plist"]] ?: @{@"message":@"SSH has not been checked yet"};
}
NSDictionary *LIKSSHAction(NSString *action) {
    NSString *error=LIKPrepareJournal();if(error)return @{@"error":error};
    if(LIKInstallationBusy())return @{@"error":@"Wait for the current installation step before changing SSH"};
    NSString *lockfile=[LIKJournal() stringByAppendingPathComponent:@"workflow.lock"];
    int lock=open(lockfile.fileSystemRepresentation,O_CREAT|O_RDWR|O_NOFOLLOW|O_CLOEXEC,0600);
    if(lock<0 || flock(lock,LOCK_EX|LOCK_NB)){if(lock>=0)close(lock);return @{@"error":@"Another SSH action is still running"};}
    NSMutableDictionary *result=[NSMutableDictionary dictionaryWithDictionary:@{@"action":action,@"time":NSDate.date.description}];
    BOOL restart=![action isEqual:@"check-ssh"];
    if([action isEqual:@"fix-ssh"] || [action isEqual:@"reinstall-ssh"]) {
        NSUInteger changed=0;error=LIKRepairFiles([action isEqual:@"reinstall-ssh"],&changed);
        result[@"files_replaced"]=@(changed);if(error)result[@"error"]=error;
    }
    if(!result[@"error"] && restart) {
        NSDictionary *config=LIKRun(@"/usr/lik/sshd",@[@"-t",@"-f",[LIK_DIR stringByAppendingPathComponent:@"sshd_config"]]);result[@"config_test"]=config;
        if(!LIKOK(config))result[@"error"]=@"SSH configuration test failed";
        if(!result[@"error"]) {
            NSString *ctl=[LIK_DIR stringByAppendingPathComponent:@"launchctl"];
            result[@"unload"]=LIKRun(ctl,@[@"unload",LIK_SSH_PLIST]);
            NSDictionary *load=LIKRun(ctl,@[@"load",LIK_SSH_PLIST]);result[@"load"]=load;
            if(!LIKOK(load))result[@"error"]=@"SSH service could not be started";
            for(int i=0;i<20&&!LIKSSHListening();i++)usleep(250000);
        }
    }
    if(!result[@"error"]) {
        NSDictionary *test=SelfTest(restart && ![action isEqual:@"restart-ssh"]);result[@"authentication_test"]=test;
        if(![test[@"authenticated"] boolValue])result[@"error"]=test[@"error"] ?: @"SSH authentication was not confirmed";
    }
    result[@"listening"]=@(LIKSSHListening());result[@"success"]=@(!result[@"error"]);
    [result writeToFile:[LIKJournal() stringByAppendingPathComponent:@"ssh-check.plist"] atomically:YES];close(lock);return result;
}
