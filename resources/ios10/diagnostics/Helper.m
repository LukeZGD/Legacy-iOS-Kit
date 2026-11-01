#import "Diagnostics.h"
#import "Installer.h"
#import <CoreFoundation/CoreFoundation.h>
#import <CommonCrypto/CommonDigest.h>
// Private iOS 10 LaunchServices interface; availability is checked at runtime.
@interface NSObject (LIKApplicationWorkspace)
+ (id)defaultWorkspace;
- (BOOL)registerApplication:(NSURL *)url;
@end
#import <sys/socket.h>
#import <sys/un.h>
#import <sys/stat.h>
#import <signal.h>
#import <unistd.h>
#import <errno.h>

static NSDictionary *LIKRegisterApp(void) {
    CFPreferencesSetValue(CFSTR("SBShowNonDefaultSystemApps"),kCFBooleanTrue,CFSTR("com.apple.springboard"),CFSTR("mobile"),kCFPreferencesAnyHost);
    BOOL preferences=CFPreferencesSynchronize(CFSTR("com.apple.springboard"),CFSTR("mobile"),kCFPreferencesAnyHost);
    Class cls=NSClassFromString(@"LSApplicationWorkspace");SEL get=NSSelectorFromString(@"defaultWorkspace"), reg=NSSelectorFromString(@"registerApplication:");
    id workspace=cls && [cls respondsToSelector:get] ? [cls defaultWorkspace] : nil;
    BOOL available=workspace && [workspace respondsToSelector:reg];
    BOOL registered=available ? [workspace registerApplication:[NSURL fileURLWithPath:LIK_APP isDirectory:YES]] : NO;
    return @{@"visibility_preference_saved":@(preferences),@"registration_api_available":@(available),@"registered":@(registered)};
}
static NSDictionary *LIKAction(NSString *action, NSDictionary *registration) {
    LIKVerifyOrdinaryBoot();
    NSMutableDictionary *result=[NSMutableDictionary dictionaryWithDictionary:@{@"root_helper_responded":@YES,@"helper_version":@"9",@"registration":registration ?: @{},@"action":action}];
    if([action isEqual:@"install"])[result addEntriesFromDictionary:LIKStartInstall()];
    else if([action isEqual:@"reboot-and-verify"])[result addEntriesFromDictionary:LIKStartReboot()];
    else if([@[@"restart-ssh",@"fix-ssh",@"reinstall-ssh"] containsObject:action])result[@"ssh_action"]=LIKSSHAction(action);
    else if([action isEqual:@"checks"])result[@"ssh_action"]=LIKSSHAction(@"check-ssh");
    result[@"snapshot"]=LIKSnapshot();
    NSMutableDictionary *workflow=[LIKWorkflow() mutableCopy];workflow[@"worker_running"]=@(LIKInstallationBusy());result[@"workflow"]=workflow;
    result[@"installer_logs"]=LIKInstallerLogs();
    if([action isEqual:@"export-logs"]) {
        NSMutableDictionary *logs=[NSMutableDictionary dictionary];NSString *j=LIKJournal();
        if(j)for(NSString *name in @[@"bootstrap.log",@"untether.log",@"verification.log",@"ondevice-install.log",@"ondevice-reboot.log"])
            logs[name]=LIKReadExportLog([j stringByAppendingPathComponent:name]);
        logs[@"helper.log"]=LIKReadExportLog(@"/var/log/lik-ios10-diagnostics.log");
        logs[@"ssh.log"]=LIKReadExportLog(@"/var/log/lik-ios10-transport.log");
        result[@"installer_logs"]=logs;
    }
    result[@"ssh_check"]=LIKSSHLastResult();result[@"helper_log"]=LIKReadTail(@"/var/log/lik-ios10-diagnostics.log");
    return result;
}
int main(int argc,char **argv) {
    @autoreleasepool {
        if(argc==2 && strcmp(argv[1],"--snapshot")==0) {
            NSData *json=[NSJSONSerialization dataWithJSONObject:LIKSnapshot() options:NSJSONWritingPrettyPrinted error:nil];write(1,json.bytes,json.length);return 0;
        }
        if(geteuid()!=0){fprintf(stderr,"Root helper requires uid 0\n");return 1;}
        signal(SIGPIPE,SIG_IGN);umask(0077);
        if(argc==2 && !strcmp(argv[1],"--install"))return LIKInstallWorker();
        if(argc==2 && !strcmp(argv[1],"--reboot"))return LIKRebootWorker();
        // These libraries are all supplied by stock iOS. No private OpenSSL or shell is needed.
        NSDictionary *registration=@{};
        fprintf(stderr,"Root helper starting (uid %d)\n",geteuid());
        int server=socket(AF_UNIX,SOCK_STREAM,0);if(server<0)return 2;
        struct sockaddr_un address={0};address.sun_family=AF_UNIX;address.sun_len=sizeof(address);strlcpy(address.sun_path,LIK_SOCKET,sizeof(address.sun_path));
        struct stat st;if(lstat(LIK_SOCKET,&st)==0){if(!S_ISSOCK(st.st_mode)||st.st_uid!=0)return 3;unlink(LIK_SOCKET);}
        if(bind(server,(struct sockaddr *)&address,sizeof(address)) || chown(LIK_SOCKET,0,501) || chmod(LIK_SOCKET,0660) || listen(server,4)){perror("diagnostic socket");return 4;}
        NSString *journalError=LIKPrepareJournal();if(journalError)fprintf(stderr,"Journal: %s\n",journalError.UTF8String);
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT,0),^{@autoreleasepool{LIKSSHAction(@"start-ssh");}});
        NSTimeInterval registrationTime=[NSDate timeIntervalSinceReferenceDate];
        for(;;) {
            @autoreleasepool {
                fd_set fds;FD_ZERO(&fds);FD_SET(server,&fds);struct timeval poll={10,0};
                int ready=select(server+1,&fds,NULL,NULL,&poll);
                if(![registration[@"registered"] boolValue] && [NSDate timeIntervalSinceReferenceDate]-registrationTime>10){registration=LIKRegisterApp();registrationTime=[NSDate timeIntervalSinceReferenceDate];}
                LIKVerifyOrdinaryBoot();
                if(ready<=0)continue;
                int client=accept(server,NULL,NULL);if(client<0)continue;
                uid_t uid;gid_t gid;struct timeval timeout={10,0};setsockopt(client,SOL_SOCKET,SO_RCVTIMEO,&timeout,sizeof(timeout));setsockopt(client,SOL_SOCKET,SO_SNDTIMEO,&timeout,sizeof(timeout));
                if(getpeereid(client,&uid,&gid) || (uid!=0 && uid!=501)){close(client);continue;}
                char buffer[32]={0};NSUInteger used=0;BOOL complete=NO;
                while(used<sizeof(buffer)-1){ssize_t n=read(client,buffer+used,1);if(n!=1)break;if(buffer[used++]=='\n'){complete=YES;break;}}
                NSString *action=complete ? [[NSString alloc] initWithBytes:buffer length:used-1 encoding:NSUTF8StringEncoding] : nil;
                if(![@[@"status",@"export-logs",@"checks",@"install",@"reboot-and-verify",@"restart-ssh",@"fix-ssh",@"reinstall-ssh"] containsObject:action]){close(client);continue;}
                if(![action isEqual:@"status"])fprintf(stderr,"Request: %s (peer uid %d)\n",action.UTF8String,uid);
                NSDictionary *result=LIKAction(action,registration);
                NSData *json=[NSJSONSerialization dataWithJSONObject:result options:0 error:nil];
                const char *bytes=json.bytes;NSUInteger sent=0;while(sent<json.length){ssize_t n=write(client,bytes+sent,json.length-sent);if(n<=0)break;sent+=(NSUInteger)n;}
                close(client);if(![action isEqual:@"status"])fprintf(stderr,"Result: %s\n",result[@"error"] ? [result[@"error"] UTF8String] : "Checks completed; inspect individual results");
            }
        }
    }
}
