#import "Diagnostics.h"
#import "Installer.h"
#import <sys/sysctl.h>
#import <sys/stat.h>
#import <sys/file.h>
#import <fcntl.h>
#import <signal.h>
#import <unistd.h>
#import <errno.h>

static BOOL OK(NSDictionary *r){return r[@"exit_code"] && [r[@"exit_code"] intValue]==0 && ![r[@"timed_out"] boolValue];}
NSString *LIKJournal(void) {
    NSString *identity=[NSString stringWithContentsOfFile:[LIK_DIR stringByAppendingPathComponent:@"identity"] encoding:NSUTF8StringEncoding error:nil];
    NSString *session=[[identity componentsSeparatedByString:@"\n"] firstObject];
    if(session.length!=36 || [session rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:@"abcdef0123456789-"] invertedSet]].location!=NSNotFound)return nil;
    return [@"/var/root/lik-ios10" stringByAppendingPathComponent:session];
}
NSString *LIKBootIdentity(void) {
    struct timeval boot={0};size_t size=sizeof(boot);
    if(sysctlbyname("kern.boottime",&boot,&size,NULL,0))return nil;
    return [NSString stringWithFormat:@"%lld:%d",(long long)boot.tv_sec,(int)boot.tv_usec];
}
NSString *LIKNextInstallStep(NSString *phase) {
    if([phase isEqual:@"new"] || [phase isEqual:@"Not started (no installer journal)"])return @"bootstrap";
    if([phase isEqual:@"needs-settings"])return @"settings";
    if([phase isEqual:@"settings-ready"])return @"untether";
    if([phase isEqual:@"untether-installed"])return @"verify";
    return nil;
}
NSString *LIKPrepareJournal(void) {
    if(geteuid()!=0)return @"Root helper is not running as root";
    NSString *j=LIKJournal();if(!j)return @"Staged identity is unreadable or invalid";
    BOOL created=NO;
    for(NSString *p in @[@"/var/root/lik-ios10",j]) {
        struct stat st;
        if(lstat(p.fileSystemRepresentation,&st)==0) {
            if(!S_ISDIR(st.st_mode)||st.st_uid!=0||(st.st_mode&0077))return @"Installer journal ownership or permissions are invalid";
        } else {
            if(errno!=ENOENT || mkdir(p.fileSystemRepresentation,0700))return @"Could not create private installer journal";
            if([p isEqual:j])created=YES;
        }
    }
    if(created) {
        NSData *identity=[NSData dataWithContentsOfFile:[LIK_DIR stringByAppendingPathComponent:@"identity"]];
        if(!identity || ![identity writeToFile:[j stringByAppendingPathComponent:@"identity"] atomically:YES] || ![@"new\n" writeToFile:[j stringByAppendingPathComponent:@"phase"] atomically:YES encoding:NSUTF8StringEncoding error:nil])return @"Could not initialize the installer journal";
    }
    NSData *expected=[NSData dataWithContentsOfFile:[LIK_DIR stringByAppendingPathComponent:@"identity"]];
    struct stat identityStat;
    NSString *journalIdentity=[j stringByAppendingPathComponent:@"identity"];
    if(lstat(journalIdentity.fileSystemRepresentation,&identityStat) || !S_ISREG(identityStat.st_mode) || identityStat.st_uid!=0 || ![expected isEqual:[NSData dataWithContentsOfFile:journalIdentity]])return @"Journal identity does not match this restore";
    return nil;
}
NSDictionary *LIKWorkflow(void) {
    NSString *j=LIKJournal();if(!j)return @{@"state":@"unavailable",@"message":@"Root helper cannot read the staged identity"};
    NSDictionary *s=[NSDictionary dictionaryWithContentsOfFile:[j stringByAppendingPathComponent:@"workflow.plist"]];
    return s ?: @{@"state":@"not-started",@"message":@"Ready to install on this device",@"completed_steps":@0,@"total_steps":@5};
}
static BOOL SaveState(NSString *state,NSString *message,int steps,NSDictionary *extra) {
    NSString *j=LIKJournal();if(!j)return NO;
    NSMutableDictionary *d=[LIKWorkflow() mutableCopy];
    [d addEntriesFromDictionary:@{@"state":state,@"message":message ?: @"",@"completed_steps":@(steps),@"total_steps":@5,@"updated":[NSDate date].description}];
    if(extra)[d addEntriesFromDictionary:extra];
    BOOL result=[d writeToFile:[j stringByAppendingPathComponent:@"workflow.plist"] atomically:YES];sync();return result;
}
static int WorkerLock(BOOL create) {
    NSString *j=LIKJournal();if(!j)return -1;
    int fd=open([[j stringByAppendingPathComponent:@"workflow.lock"] fileSystemRepresentation],O_RDWR|O_NOFOLLOW|O_CLOEXEC|(create?O_CREAT:0),0600);
    if(fd<0)return -1;
    struct stat st;if(fstat(fd,&st)||!S_ISREG(st.st_mode)||st.st_uid!=0||flock(fd,LOCK_EX|LOCK_NB)){close(fd);return -1;}
    return fd;
}
BOOL LIKInstallationBusy(void) {
    NSString *j=LIKJournal();if(!j)return NO;
    if(access([[j stringByAppendingPathComponent:@"workflow.lock"] fileSystemRepresentation],F_OK))return NO;
    int fd=WorkerLock(NO);if(fd<0)return YES;close(fd);return NO;
}
static NSDictionary *StartJob(NSString *name) {
    NSString *plist=[LIK_DIR stringByAppendingPathComponent:[name stringByAppendingString:@".plist"]];
    NSString *ctl=[LIK_DIR stringByAppendingPathComponent:@"launchctl"];
    LIKRun(ctl,@[@"unload",plist]);
    NSDictionary *load=LIKRun(ctl,@[@"load",plist]);
    return OK(load)?@{@"accepted":@YES,@"message":@"Started on-device job"}:@{@"error":@"Could not start the on-device job",@"launchctl":load};
}
NSDictionary *LIKStartInstall(void) {
    NSString *error=LIKPrepareJournal();if(error)return @{@"error":error};
    if(LIKInstallationBusy())return @{@"accepted":@YES,@"message":@"A local task is running. Wait for it to finish, then tap Install / Continue."};
    NSDictionary *snapshot=LIKSnapshot();
    if(![snapshot[@"jumpstart_marker_present"] boolValue])return @{@"error":@"The temporary jump-start boot was not confirmed. No packages were changed.",@"snapshot":snapshot};
    if(!LIKNextInstallStep(LIKPhase()))return @{@"error":@"The previous package step did not finish cleanly. Export Logs before attempting recovery.",@"phase":LIKPhase()};
    if([LIKWorkflow()[@"state"] isEqual:@"complete"])return @{@"error":@"Installation is already complete"};
    return StartJob(@"ondevice-install");
}
static NSString *ApplySettings(void) {
    NSString *path=@"/var/mobile/Library/Preferences/com.apple.springboard.plist";
    NSData *old=[NSData dataWithContentsOfFile:path];
    NSPropertyListFormat format=NSPropertyListXMLFormat_v1_0;NSError *error=nil;
    id plist=old?[NSPropertyListSerialization propertyListWithData:old options:NSPropertyListMutableContainers format:&format error:&error]:[NSMutableDictionary dictionary];
    if(![plist isKindOfClass:NSMutableDictionary.class])return @"Existing SpringBoard preferences could not be parsed; they were preserved";
    NSString *backup=[LIKJournal() stringByAppendingPathComponent:@"springboard.original.plist"];
    if(old && ![[NSFileManager defaultManager] fileExistsAtPath:backup] && ![old writeToFile:backup options:NSDataWritingAtomic error:&error])return error.localizedDescription;
    plist[@"SBShowNonDefaultSystemApps"]=@YES;
    NSData *data=[NSPropertyListSerialization dataWithPropertyList:plist format:format options:0 error:&error];
    if(!data || ![data writeToFile:path options:NSDataWritingAtomic error:&error])return error.localizedDescription ?: @"Could not save SpringBoard preferences";
    if(chown(path.fileSystemRepresentation,501,501)||chmod(path.fileSystemRepresentation,0600))return @"Could not set SpringBoard preference ownership";
    NSDictionary *r=LIKRunTimed(@"/usr/lik/bash",@[[LIK_DIR stringByAppendingPathComponent:@"local-install.sh"],@"settings"],60);
    return OK(r)?nil:[@"Package manager configuration failed: " stringByAppendingString:r.description];
}
int LIKInstallWorker(void) {
    NSString *error=LIKPrepareJournal();if(error){fprintf(stderr,"%s\n",error.UTF8String);return 1;}
    int lock=WorkerLock(YES);if(lock<0)return 1;
    NSString *boot=LIKBootIdentity();
    if(!boot){close(lock);return 1;}
    for(int i=0;i<4;i++) {
        NSString *step=LIKNextInstallStep(LIKPhase());
        if(!step){error=@"Installer stopped in an incomplete package phase. It will not blindly repeat that step.";break;}
        NSDictionary *r=nil;
        if([step isEqual:@"bootstrap"]) {
            if(!SaveState(@"installing",@"Installing jailbreak assets and Zebra",0,@{@"installation_boot":boot})){error=@"Could not save installation state";break;}
            r=LIKRunLogged(@"/usr/lik/bash",@[[LIK_DIR stringByAppendingPathComponent:@"install.sh"],@"bootstrap"],1200,[LIKJournal() stringByAppendingPathComponent:@"bootstrap.log"]);
        } else if([step isEqual:@"settings"]) {
            if(!SaveState(@"installing",@"Configuring the package manager",1,nil)){error=@"Could not save installation state";break;}
            error=ApplySettings();if(error)break;
            continue;
        } else if([step isEqual:@"untether"]) {
            if(!SaveState(@"installing",@"Installing Procyon and generating its boot stages",2,nil)){error=@"Could not save installation state";break;}
            r=LIKRunLogged(@"/usr/lik/bash",@[[LIK_DIR stringByAppendingPathComponent:@"install.sh"],@"untether"],1800,[LIKJournal() stringByAppendingPathComponent:@"untether.log"]);
        } else {
            if(!SaveState(@"installing",@"Verifying the persistent untether installation",3,nil)){error=@"Could not save installation state";break;}
            r=LIKRunLogged(@"/usr/lik/bash",@[[LIK_DIR stringByAppendingPathComponent:@"local-install.sh"],@"verify"],120,[LIKJournal() stringByAppendingPathComponent:@"verification.log"]);
            if(OK(r)) {
                BOOL saved=SaveState(@"reboot-required",@"Installation verified. Tap Reboot and Verify to test an ordinary boot.",4,@{@"persistent_setup_verified":@YES,@"installation_boot":boot});
                close(lock);return saved?0:1;
            }
        }
        if(!OK(r)){error=[NSString stringWithFormat:@"The %@ step failed. Its log is available in Export Logs. Result: %@",step,r];break;}
    }
    SaveState(@"error",error ?: @"Installer did not reach verification",[LIKWorkflow()[@"completed_steps"] intValue],nil);
    fprintf(stderr,"%s\n",(error ?: @"Incomplete installation").UTF8String);close(lock);return 1;
}
NSDictionary *LIKStartReboot(void) {
    NSString *error=LIKPrepareJournal();if(error)return @{@"error":error};
    NSDictionary *w=LIKWorkflow();
    if(LIKInstallationBusy() || ![@[@"reboot-required",@"awaiting-ordinary-boot"] containsObject:w[@"state"]] || ![w[@"persistent_setup_verified"] boolValue] || ![LIKPhase() isEqual:@"untether-installed"])
        return @{@"error":@"Installation must finish and pass verification before reboot"};
    if(![LIKSnapshot()[@"jumpstart_marker_present"] boolValue])return @{@"error":@"This is already an ordinary boot; use Run checks to verify it"};
    return StartJob(@"ondevice-reboot");
}
int LIKRebootWorker(void) {
    int lock=WorkerLock(YES);if(lock<0)return 1;
    NSDictionary *w=LIKWorkflow();NSString *boot=LIKBootIdentity();
    if(!boot || ![@[@"reboot-required",@"awaiting-ordinary-boot"] containsObject:w[@"state"]] || ![w[@"persistent_setup_verified"] boolValue]){close(lock);return 1;}
    NSDictionary *verified=LIKRunTimed(@"/usr/lik/bash",@[[LIK_DIR stringByAppendingPathComponent:@"local-install.sh"],@"verify"],120);
    if(!OK(verified)){SaveState(@"error",@"Pre-reboot verification failed; the phone has not been rebooted",4,@{@"verification_error":verified});close(lock);return 1;}
    if(!SaveState(@"awaiting-ordinary-boot",@"Waiting for an ordinary boot. Reopen the app after reboot.",4,@{@"pre_reboot_boot":boot})){close(lock);return 1;}
    sync();sleep(2);
    NSDictionary *r=LIKRun(@"/sbin/reboot",@[]);
    if(!OK(r))SaveState(@"reboot-required",@"Reboot request failed. You can retry Reboot and Verify.",4,@{@"reboot_error":r});
    close(lock);return OK(r)?0:1;
}
BOOL LIKOrdinaryBootReady(NSDictionary *w, NSString *boot, NSDictionary *s, BOOL springboard) {
    return [w[@"state"] isEqual:@"awaiting-ordinary-boot"] && [w[@"persistent_setup_verified"] boolValue]
        && boot.length && [w[@"pre_reboot_boot"] length] && ![boot isEqual:w[@"pre_reboot_boot"]]
        && [s[@"boot_arguments_readable"] boolValue] && ![s[@"jumpstart_marker_present"] boolValue]
        && s[@"euid"] && [s[@"euid"] intValue]==0 && [s[@"kernel_task_access"][@"success"] boolValue] && springboard;
}
void LIKVerifyOrdinaryBoot(void) {
    NSDictionary *w=LIKWorkflow();NSString *boot=LIKBootIdentity();
    if(![w[@"state"] isEqual:@"awaiting-ordinary-boot"] || !boot || [boot isEqual:w[@"pre_reboot_boot"]])return;
    NSDictionary *s=LIKSnapshot();
    int mib[]={CTL_KERN,KERN_PROC,KERN_PROC_ALL,0};size_t size=0;
    if(sysctl(mib,4,NULL,&size,NULL,0))return;
    NSMutableData *data=[NSMutableData dataWithLength:size];if(sysctl(mib,4,data.mutableBytes,&size,NULL,0))return;
    const struct kinfo_proc *procs=data.bytes;BOOL springboard=NO;
    for(size_t i=0;i<size/sizeof(*procs);i++)if(!strcmp(procs[i].kp_proc.p_comm,"SpringBoard")){springboard=YES;break;}
    if(LIKOrdinaryBootReady(w,boot,s,springboard))SaveState(@"complete",@"Untethered boot verified. Installation is complete.",5,@{@"ordinary_boot":boot,@"verification":s});
}
NSDictionary *LIKInstallerLogs(void) {
    NSMutableDictionary *logs=[NSMutableDictionary dictionary];NSString *j=LIKJournal();if(!j)return logs;
    for(NSString *name in @[@"bootstrap.log",@"untether.log",@"verification.log",@"ondevice-install.log",@"ondevice-reboot.log",@"last-exit-code",@"procyon-exit-code"])
        logs[name]=LIKReadTail([j stringByAppendingPathComponent:name]);
    return logs;
}
