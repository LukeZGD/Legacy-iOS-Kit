#import "Diagnostics.h"
#import <mach/mach.h>
#import <sys/sysctl.h>
#import <sys/socket.h>
#import <sys/un.h>
#import <netinet/in.h>
#import <arpa/inet.h>
#import <sys/stat.h>
#import <sys/wait.h>
#import <spawn.h>
#import <fcntl.h>
#import <signal.h>
#import <unistd.h>
#import <errno.h>
extern char **environ;

static NSString *LIKError(int code) { return [NSString stringWithFormat:@"%s (%d)", strerror(code), code]; }
static NSString *LIKSysctl(const char *name) {
    char data[4096] = {0}; size_t size = sizeof(data)-1;
    if (sysctlbyname(name, data, &size, NULL, 0)) return [@"Unavailable: " stringByAppendingString:LIKError(errno)];
    return [NSString stringWithUTF8String:data] ?: @"Unavailable: non-UTF8 value";
}
NSString *LIKReadTail(NSString *path) {
    int fd = open(path.fileSystemRepresentation, O_RDONLY | O_NOFOLLOW);
    if (fd < 0) return [@"Unreadable: " stringByAppendingString:LIKError(errno)];
    struct stat st; if (fstat(fd,&st) || !S_ISREG(st.st_mode)) { close(fd); return @"Not a regular file"; }
    if (st.st_size > 16384) lseek(fd, st.st_size-16384, SEEK_SET);
    char bytes[16385]; ssize_t count=read(fd, bytes, 16384); int error=errno; close(fd);
    if (count<0) return LIKError(error);
    return [[NSString alloc] initWithBytes:bytes length:(NSUInteger)count encoding:NSUTF8StringEncoding] ?: @"Non-UTF8 log data";
}
NSString *LIKReadExportLog(NSString *path) {
    int fd=open(path.fileSystemRepresentation,O_RDONLY|O_NOFOLLOW);if(fd<0)return [@"Unreadable: " stringByAppendingString:LIKError(errno)];
    struct stat st;if(fstat(fd,&st)||!S_ISREG(st.st_mode)){close(fd);return @"Not a regular log file";}
    BOOL truncated=st.st_size>524288;if(truncated)lseek(fd,st.st_size-524288,SEEK_SET);
    NSMutableData *data=[NSMutableData data];char b[8192];ssize_t n;
    while((n=read(fd,b,MIN(sizeof(b),524288-data.length)))>0)[data appendBytes:b length:(NSUInteger)n];
    close(fd);NSString *text=[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"Non-UTF8 log";
    return truncated?[@"[Older entries omitted; last 512 KiB follows]\n" stringByAppendingString:text]:text;
}
static NSDictionary *LIKFile(NSString *path) {
    struct stat st;
    if (lstat(path.fileSystemRepresentation,&st)) return @{@"path":path,@"present":@NO,@"error":LIKError(errno)};
    return @{@"path":path,@"present":@YES,@"bytes":@(st.st_size),@"uid":@(st.st_uid),
             @"mode":[NSString stringWithFormat:@"%04o",st.st_mode & 07777],@"readable":@(access(path.fileSystemRepresentation,R_OK)==0)};
}
BOOL LIKSSHListening(void) {
    int fd=socket(AF_INET,SOCK_STREAM,0); if(fd<0)return NO;
    struct sockaddr_in address={0}; address.sin_family=AF_INET; address.sin_len=sizeof(address);
    address.sin_port=htons(44); address.sin_addr.s_addr=htonl(INADDR_LOOPBACK);
    struct timeval timeout={1,0}; setsockopt(fd,SOL_SOCKET,SO_SNDTIMEO,&timeout,sizeof(timeout));
    BOOL success=connect(fd,(struct sockaddr *)&address,sizeof(address))==0;
    close(fd); return success;
}
NSString *LIKPhase(void) {
    NSString *identity=[NSString stringWithContentsOfFile:[LIK_DIR stringByAppendingPathComponent:@"identity"] encoding:NSUTF8StringEncoding error:nil];
    NSString *session=[[identity componentsSeparatedByString:@"\n"] firstObject];
    if(session.length!=36 || [session rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:@"abcdef0123456789-"] invertedSet]].location!=NSNotFound) return @"Unknown: identity unreadable/invalid";
    NSString *path=[NSString stringWithFormat:@"/var/root/lik-ios10/%@/phase",session];
    NSString *phase=[NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
    if(phase)return [phase stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if(geteuid()!=0)return @"Unknown: root helper needed";
    struct stat st;
    if(lstat(path.stringByDeletingLastPathComponent.fileSystemRepresentation,&st)==0 || errno!=ENOENT)return @"Unknown: journal phase is unreadable";
    return @"Not started (no installer journal)";
}
NSDictionary *LIKSnapshot(void) {
    NSMutableDictionary *result=[NSMutableDictionary dictionary];
    result[@"time"]=[[NSDate date] description]; result[@"uid"]=@(getuid()); result[@"euid"]=@(geteuid()); result[@"pid"]=@(getpid());
    result[@"device"]=LIKSysctl("hw.machine"); result[@"board"]=LIKSysctl("hw.model"); result[@"build"]=LIKSysctl("kern.osversion");
    NSString *args=LIKSysctl("kern.bootargs"); result[@"boot_arguments"]=args;
    result[@"boot_arguments_readable"]=@(![args hasPrefix:@"Unavailable:"]);
    result[@"jumpstart_marker_present"]=@([[args componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] containsObject:@"lik_ios10_jumpstart=1"]);
    mach_port_t port=MACH_PORT_NULL; kern_return_t kr=task_for_pid(mach_task_self(),0,&port);
    result[@"kernel_task_access"]=@{@"success":@(kr==KERN_SUCCESS && MACH_PORT_VALID(port)),@"code":@(kr),@"message":[NSString stringWithUTF8String:mach_error_string(kr)]};
    if(MACH_PORT_VALID(port)) mach_port_deallocate(mach_task_self(),port);
    NSMutableArray *files=[NSMutableArray array];
    for(NSString *path in @[@"/usr/lik/sshd",@"/usr/lik/bash",@"/usr/lik/libcrypto.0.9.8.dylib",@"/usr/lik/libssl.0.9.8.dylib",LIK_SSH_PLIST,@"/System/Library/LaunchDaemons/org.legacyioskit.ios10.diagnostics.plist",[LIK_DIR stringByAppendingPathComponent:@"diagnostic-helper"],
            [LIK_DIR stringByAppendingPathComponent:@"sshd_config"],[LIK_DIR stringByAppendingPathComponent:@"bootstrap.tar"],
            [LIK_DIR stringByAppendingPathComponent:@"zebra.deb"],[LIK_DIR stringByAppendingPathComponent:@"procyon.deb"],
            @"/usr/bin/procyon",@"/Applications/Zebra.app",@"/.installed_socket",@"/var/lib/dpkg/status",@"/etc/racoon/stage2"])
        [files addObject:LIKFile(path)];
    result[@"files"]=files;
    result[@"ssh_port_44_accepting_connections"]=@(LIKSSHListening());
    NSString *pidText=[NSString stringWithContentsOfFile:@"/var/run/lik-ios10-sshd.pid" encoding:NSUTF8StringEncoding error:nil];
    int pid=pidText.intValue; result[@"ssh_pid_file"]=pidText ?: @"Absent or unreadable";
    if(pid>1) {
        struct kinfo_proc proc={0}; size_t size=sizeof(proc); int mib[]={CTL_KERN,KERN_PROC,KERN_PROC_PID,pid};
        int rc=sysctl(mib,4,&proc,&size,NULL,0);
        result[@"ssh_process_verified"]=@(rc==0 && size==sizeof(proc) && strcmp(proc.kp_proc.p_comm,"sshd")==0);
        result[@"ssh_process_note"]=rc==0 ? @"Matched PID file against kernel process name; port check is separate" : LIKError(errno);
    } else result[@"ssh_process_verified"]=@NO;
    result[@"installer_phase"]=LIKPhase();
    for(NSString *volume in @[@"/",@"/var"]) {
        NSError *error=nil;
        NSDictionary *fs=[[NSFileManager defaultManager] attributesOfFileSystemForPath:volume error:&error];
        result[[volume isEqual:@"/"] ? @"system_volume" : @"data_volume"]=fs ? @{@"free_bytes":fs[NSFileSystemFreeSize],@"total_bytes":fs[NSFileSystemSize]} : @{@"error":error.localizedDescription ?: @"Unavailable"};
    }
    result[@"transport_log"]=LIKReadTail(@"/var/log/lik-ios10-transport.log");
    result[@"limits"]=@"A launch, marker, file or one successful capability check does not prove a complete jailbreak or working untether. A listener does not prove SSH authentication works. Files marked unreadable are not necessarily missing.";
    return result;
}
NSDictionary *LIKRunTimed(NSString *path, NSArray *arguments, NSTimeInterval timeout) {
    if(arguments.count>60)return @{@"error":@"Too many fixed arguments"};
    char *argv[63]={0}; argv[0]=(char *)path.fileSystemRepresentation;
    for(NSUInteger i=0;i<arguments.count;i++) argv[i+1]=(char *)[arguments[i] UTF8String];
    int pipes[2]; if(pipe(pipes))return @{@"error":LIKError(errno)};
    posix_spawn_file_actions_t actions; posix_spawn_file_actions_init(&actions);
    posix_spawn_file_actions_addclose(&actions,pipes[0]);
    posix_spawn_file_actions_adddup2(&actions,pipes[1],STDOUT_FILENO);
    posix_spawn_file_actions_adddup2(&actions,pipes[1],STDERR_FILENO);
    posix_spawn_file_actions_addclose(&actions,pipes[1]);
    pid_t pid=0; int rc=posix_spawn(&pid,path.fileSystemRepresentation,&actions,NULL,argv,environ);
    posix_spawn_file_actions_destroy(&actions); close(pipes[1]);
    if(rc){ close(pipes[0]);return @{@"spawn_error":LIKError(rc)}; }
    fcntl(pipes[0],F_SETFL,O_NONBLOCK); NSMutableData *data=[NSMutableData data];
    NSTimeInterval deadline=[NSDate timeIntervalSinceReferenceDate]+timeout; int status=0; BOOL done=NO;
    do {
        char b[1024]; ssize_t n;
        while((n=read(pipes[0],b,sizeof(b)))>0)if(data.length<16384)[data appendBytes:b length:MIN((NSUInteger)n,16384-data.length)];
        pid_t wait=waitpid(pid,&status,WNOHANG); if(wait==pid){done=YES;break;}
        if(wait<0)break;
        usleep(50000);
    } while([NSDate timeIntervalSinceReferenceDate]<deadline);
    if(!done){kill(pid,SIGKILL);waitpid(pid,&status,0);}
    char b[1024];ssize_t n;while((n=read(pipes[0],b,sizeof(b)))>0)if(data.length<16384)[data appendBytes:b length:MIN((NSUInteger)n,16384-data.length)];
    close(pipes[0]);
    return @{@"executable":path,@"arguments":arguments,@"timed_out":@(!done),
             @"exit_code":@(WIFEXITED(status)?WEXITSTATUS(status):-1),@"signal":@(WIFSIGNALED(status)?WTERMSIG(status):0),
             @"output":[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"Non-UTF8 output"};
}
NSDictionary *LIKRun(NSString *path, NSArray *arguments) { return LIKRunTimed(path,arguments,12); }
NSDictionary *LIKRunLogged(NSString *path, NSArray *arguments, NSTimeInterval timeout, NSString *logPath) {
    if(arguments.count>60)return @{@"error":@"Too many arguments"};
    int fd=open(logPath.fileSystemRepresentation,O_WRONLY|O_CREAT|O_APPEND|O_NOFOLLOW,0600);
    if(fd<0)return @{@"error":LIKError(errno)};
    char *argv[63]={0};argv[0]=(char *)path.fileSystemRepresentation;
    for(NSUInteger i=0;i<arguments.count;i++)argv[i+1]=(char *)[arguments[i] UTF8String];
    posix_spawn_file_actions_t actions;posix_spawn_file_actions_init(&actions);
    posix_spawn_file_actions_adddup2(&actions,fd,1);posix_spawn_file_actions_adddup2(&actions,fd,2);posix_spawn_file_actions_addclose(&actions,fd);
    posix_spawnattr_t attr;posix_spawnattr_init(&attr);posix_spawnattr_setflags(&attr,POSIX_SPAWN_SETPGROUP);posix_spawnattr_setpgroup(&attr,0);
    pid_t pid=0;int rc=posix_spawn(&pid,path.fileSystemRepresentation,&actions,&attr,argv,environ);
    posix_spawn_file_actions_destroy(&actions);posix_spawnattr_destroy(&attr);close(fd);
    if(rc)return @{@"spawn_error":LIKError(rc)};
    NSTimeInterval deadline=[NSDate timeIntervalSinceReferenceDate]+timeout;int status=0;BOOL done=NO;
    do {pid_t waited=waitpid(pid,&status,WNOHANG);if(waited==pid){done=YES;break;}if(waited<0)break;usleep(100000);}while([NSDate timeIntervalSinceReferenceDate]<deadline);
    if(!done){kill(-pid,SIGTERM);sleep(1);kill(-pid,SIGKILL);waitpid(pid,&status,0);}
    return @{@"exit_code":@(WIFEXITED(status)?WEXITSTATUS(status):-1),@"signal":@(WIFSIGNALED(status)?WTERMSIG(status):0),@"timed_out":@(!done),@"log":logPath,@"tail":LIKReadTail(logPath)};
}
NSString *LIKExportReport(NSString *report, NSError **error) {
    NSString *directory=LIK_EXPORT_DIR;
    if(![[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:error])return nil;
    NSDateFormatter *formatter=[NSDateFormatter new];formatter.locale=[[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];formatter.timeZone=[NSTimeZone timeZoneForSecondsFromGMT:0];formatter.dateFormat=@"yyyyMMdd-HHmmss";
    NSString *name=[NSString stringWithFormat:@"iOS10-%@-%@.txt",[formatter stringFromDate:NSDate.date],[[NSUUID UUID].UUIDString substringToIndex:8]];
    NSString *path=[directory stringByAppendingPathComponent:name];
    if(![report writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:error])return nil;
    return [@"/Downloads/Legacy-iOS-Kit/Logs" stringByAppendingPathComponent:name];
}
NSDictionary *LIKRequest(NSString *command) {
    if(![@[@"status",@"export-logs",@"checks",@"install",@"reboot-and-verify",@"restart-ssh",@"fix-ssh",@"reinstall-ssh"] containsObject:command])return @{@"error":@"Unknown diagnostic action"};
    int fd=socket(AF_UNIX,SOCK_STREAM,0);if(fd<0)return @{@"error":LIKError(errno)};
    struct sockaddr_un address={0}; address.sun_family=AF_UNIX;address.sun_len=sizeof(address);
    strlcpy(address.sun_path,LIK_SOCKET,sizeof(address.sun_path));
    struct timeval timeout={90,0};setsockopt(fd,SOL_SOCKET,SO_RCVTIMEO,&timeout,sizeof(timeout));setsockopt(fd,SOL_SOCKET,SO_SNDTIMEO,&timeout,sizeof(timeout));
    if(connect(fd,(struct sockaddr *)&address,sizeof(address))){int e=errno;close(fd);return @{@"error":LIKError(e),@"root_helper_responded":@NO};}
    NSData *request=[[command stringByAppendingString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding];
    if(write(fd,request.bytes,request.length)!=(ssize_t)request.length){int e=errno;close(fd);return @{@"error":LIKError(e)};}
    shutdown(fd,SHUT_WR);NSMutableData *data=[NSMutableData data];char buffer[4096];ssize_t n;
    while((n=read(fd,buffer,sizeof(buffer)))>0) {
        if(data.length+(NSUInteger)n>([command isEqual:@"export-logs"] ? 8*1024*1024 : 262144)){close(fd);return @{@"error":@"Helper response exceeds size limit"};}
        [data appendBytes:buffer length:(NSUInteger)n];
    }
    int e=errno;close(fd);
    if(n<0)return @{@"error":LIKError(e),@"root_helper_responded":@(data.length>0)};
    NSError *error=nil;id result=[NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
    if(![result isKindOfClass:[NSDictionary class]])return @{@"error":error.localizedDescription ?: @"Invalid helper response"};
    return result;
}
