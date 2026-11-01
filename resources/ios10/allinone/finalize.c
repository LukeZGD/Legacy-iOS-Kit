/* Restore-only finalizer; no exploit or jailbreak is run in the restore kernel. */
#include <CoreFoundation/CoreFoundation.h>
#include <CommonCrypto/CommonDigest.h>
#include <sys/mount.h>
#include <sys/stat.h>
#include <sys/sysctl.h>
#include <fcntl.h>
#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <dirent.h>
#include "pathmap.h"
#define BASE "/mnt1/usr/local/share/lik-aio"
int install(void);
static char version[32];
void lik_target_version(uint32_t *out){sscanf(version,"%u.%u.%u",out,out+1,out+2);}
__attribute__((noreturn)) static void die(const char *why){fprintf(stderr,"[LIK-AIO] ERROR: %s (errno %d)\n",why,errno);exit(1);}
static void line(const char *s){printf("[LIK-AIO] %s\n",s);fflush(stdout);}
static CFPropertyListRef plist(const char *p){
    int fd=open(p,O_RDONLY|O_NOFOLLOW);if(fd<0)die(p);struct stat s;
    if(fstat(fd,&s)||!S_ISREG(s.st_mode)||s.st_size<=0||s.st_size>16*1024*1024)die("Invalid plist size");
    UInt8 *b=malloc(s.st_size);if(!b)die("allocation");size_t n=0;ssize_t r;
    while(n<(size_t)s.st_size){r=read(fd,b+n,s.st_size-n);if(r<=0)die("plist read");n+=r;}close(fd);
    CFDataRef d=CFDataCreateWithBytesNoCopy(NULL,b,n,kCFAllocatorMalloc);
    CFPropertyListRef v=CFPropertyListCreateWithData(NULL,d,kCFPropertyListMutableContainersAndLeaves,NULL,NULL);
    CFRelease(d);if(!v)die("plist parse");return v;
}
static void str(CFDictionaryRef d,CFStringRef k,char *s,size_t n){
    CFTypeRef v=CFDictionaryGetValue(d,k);
    if(!v||CFGetTypeID(v)!=CFStringGetTypeID()||!CFStringGetCString(v,s,n,kCFStringEncodingUTF8))die("Invalid manifest string");
}
static int number(CFDictionaryRef d,CFStringRef k){int n;CFTypeRef v=CFDictionaryGetValue(d,k);
    if(!v||CFGetTypeID(v)!=CFNumberGetTypeID()||!CFNumberGetValue(v,kCFNumberIntType,&n))die("Invalid manifest number");return n;
}
static void hash(const char *p,char out[65]){
    unsigned char b[32768],sum[32];CC_SHA256_CTX c;CC_SHA256_Init(&c);
    int fd=open(p,O_RDONLY|O_NOFOLLOW);if(fd<0)die(p);ssize_t n;
    while((n=read(fd,b,sizeof b))>0)CC_SHA256_Update(&c,b,(CC_LONG)n);
    close(fd);if(n<0)die("hash read");CC_SHA256_Final(sum,&c);
    for(int i=0;i<32;i++)sprintf(out+i*2,"%02x",sum[i]);
}
static void equal(const char *a,const char *b){char x[65],y[65];hash(a,x);hash(b,y);if(strcmp(x,y))die("Procyon original backup mismatch");}
static void regular(const char *p){struct stat s;if(lstat(p,&s)||!S_ISREG(s.st_mode)||!s.st_size)die(p);}
static void mkdirs(const char *p,uid_t uid,gid_t gid){
    char b[4096];if(strlen(p)>=sizeof b)die("Path too long");strcpy(b,p);
    for(char *s=b+1;;s++){if(*s=='/'||!*s){char c=*s;*s=0;struct stat st;
        if(lstat(b,&st)){if(errno!=ENOENT||mkdir(b,0755)||chown(b,uid,gid))die(b);}
        else if(!S_ISDIR(st.st_mode))die("Non-directory archive parent");
        *s=c;if(!c)break;
    }}
}
static void writefile(const char *p,const void *b,size_t n,mode_t m,uid_t u,gid_t g){
    int fd=open(p,O_WRONLY|O_CREAT|O_TRUNC|O_NOFOLLOW,m);if(fd<0)die(p);size_t o=0;ssize_t r;
    while(o<n){r=write(fd,(const char*)b+o,n-o);if(r<=0)die("write");o+=r;}
    if(fchown(fd,u,g)||fchmod(fd,m)||fsync(fd))die("file metadata/sync");close(fd);
}
static void saveplist(const char *p,CFPropertyListRef v,uid_t u,gid_t g){
    CFDataRef d=CFPropertyListCreateData(NULL,v,kCFPropertyListXMLFormat_v1_0,0,NULL);if(!d)die("plist serialize");
    writefile(p,CFDataGetBytePtr(d),CFDataGetLength(d),0644,u,g);CFRelease(d);
}
static void datafiles(CFArrayRef a){
    if(CFGetTypeID(a)!=CFArrayGetTypeID())die("Invalid data plan");
    for(CFIndex i=0;i<CFArrayGetCount(a);i++){
        CFDictionaryRef e=CFArrayGetValueAtIndex(a,i);char rel[2048],kind[16],dst[4096],src[4096],sha[65],actual[65];
        str(e,CFSTR("path"),rel,sizeof rel);str(e,CFSTR("kind"),kind,sizeof kind);
        if(!*rel||rel[0]=='/'||strstr(rel,"..")||strstr(rel,"//"))die("Unsafe data path");
        snprintf(dst,sizeof dst,"/mnt2/%s",rel);char parent[4096];strcpy(parent,dst);*strrchr(parent,'/')=0;
        uid_t uid=number(e,CFSTR("uid"));gid_t gid=number(e,CFSTR("gid"));mode_t mode=number(e,CFSTR("mode"));
        mkdirs(parent,0,0);
        if(!strcmp(kind,"dir")){
            struct stat st;if(lstat(dst,&st)==0){if(!S_ISDIR(st.st_mode))die("Data directory collision");continue;}
            if(mkdir(dst,mode)||chown(dst,uid,gid)||chmod(dst,mode))die(dst);
        }else if(!strcmp(kind,"file")){
            char blob[32];str(e,CFSTR("blob"),blob,sizeof blob);if(strspn(blob,"0123456789")!=strlen(blob))die("Invalid blob");
            snprintf(src,sizeof src,BASE "/data/%s",blob);str(e,CFSTR("sha256"),sha,sizeof sha);hash(src,actual);
            if(strcmp(actual,sha))die("Data source checksum mismatch");
            int in=open(src,O_RDONLY|O_NOFOLLOW),out=open(dst,O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW,mode);
            if(in<0||out<0)die("Data file already exists or cannot be created");
            char buf[32768];ssize_t n;while((n=read(in,buf,sizeof buf))>0){ssize_t o=0,r;while(o<n){r=write(out,buf+o,n-o);if(r<=0)die("Data copy");o+=r;}}
            if(n<0||fchown(out,uid,gid)||fchmod(out,mode)||fsync(out))die("Data copy metadata");close(in);close(out);
            hash(dst,actual);if(strcmp(actual,sha))die("Written data checksum mismatch");
        }else if(!strcmp(kind,"link")){
            char link[2048];str(e,CFSTR("link"),link,sizeof link);
            if(symlink(link,dst)||lchown(dst,uid,gid))die("Data symlink collision");
        }else die("Unsupported data entry");
    }
}
static void mountcheck(const char *path,const char *device){struct statfs s;
    if(statfs(path,&s)||strcmp(s.f_mntonname,path)||strcmp(s.f_mntfromname,device)||strcmp(s.f_fstypename,"hfs")||(s.f_flags&MNT_RDONLY))die("Both restored HFS volumes must still be mounted read/write");
}
int main(int argc,char **argv){
    if(argc!=1||getuid()!=0)die("Restore-only invocation required");
    mountcheck("/mnt1","/dev/disk0s1s1");mountcheck("/mnt2","/dev/disk0s1s2");
    CFDictionaryRef plan=plist(BASE "/plan.plist"),sv=plist("/mnt1/System/Library/CoreServices/SystemVersion.plist");
    char expected[64],actual[64],model[64];size_t n=sizeof model;
    if(sysctlbyname("hw.machine",model,&n,NULL,0))die("Cannot read hardware model");
    str(plan,CFSTR("product"),expected,sizeof expected);if(strcmp(model,expected))die("Target device mismatch");
    str(plan,CFSTR("version"),expected,sizeof expected);str(sv,CFSTR("ProductVersion"),version,sizeof version);
    if(strcmp(expected,version))die("Target version mismatch");
    str(plan,CFSTR("build"),expected,sizeof expected);str(sv,CFSTR("ProductBuildVersion"),actual,sizeof actual);
    if(strcmp(expected,actual))die("Target build mismatch");
    if(access("/mnt2/root/procyon",F_OK)==0||access("/mnt2/lib/dpkg/status",F_OK)==0)die("Installation target is not freshly restored");
    regular("/mnt1/System/Library/Caches/com.apple.kernelcaches/kernelcache");
    regular("/mnt1/System/Library/Caches/com.apple.dyld/dyld_shared_cache_armv7s");
    regular("/mnt1/private/etc/racoon/racoon.conf");regular("/mnt1/usr/libexec/backboardd");regular("/mnt1/usr/libexec/wifiFirmwareLoaderLegacy");
    line("COPY_DATA: Apple data initialization and resize are complete");
    datafiles(CFDictionaryGetValue(plan,CFSTR("data")));
    mkdirs("/mnt2/db/com.apple.xpc.launchd",0,0);
    if(access("/mnt2/db/com.apple.xpc.launchd/disabled.plist",F_OK)){
        CFDictionaryRef empty=CFDictionaryCreate(NULL,NULL,NULL,0,&kCFTypeDictionaryKeyCallBacks,&kCFTypeDictionaryValueCallBacks);
        saveplist("/mnt2/db/com.apple.xpc.launchd/disabled.plist",empty,0,0);CFRelease(empty);
        line("Created initial empty launchd override dictionary; Procyon will preserve and replace it");
    }
    regular("/mnt2/db/com.apple.xpc.launchd/disabled.plist");
    mkdirs("/mnt2/mobile/Library/Preferences",501,501);
    const char *prefs="/mnt2/mobile/Library/Preferences/com.apple.springboard.plist";
    CFMutableDictionaryRef sb=access(prefs,F_OK)?CFDictionaryCreateMutable(NULL,0,&kCFTypeDictionaryKeyCallBacks,&kCFTypeDictionaryValueCallBacks):(CFMutableDictionaryRef)plist(prefs);
    if(CFGetTypeID(sb)!=CFDictionaryGetTypeID())die("Invalid SpringBoard preferences");
    CFDictionarySetValue(sb,CFSTR("SBShowNonDefaultSystemApps"),kCFBooleanTrue);saveplist(prefs,sb,501,501);CFRelease(sb);
    char racoon_before[65];hash("/mnt1/private/etc/racoon/racoon.conf",racoon_before);
    line("GENERATE_UNTETHER: reading installed kernelcache and full on-disk dyld cache");
    if(install()!=0)die("Procyon installation failed");
    regular("/mnt2/root/procyon/stage1/part1.conf");regular("/mnt1/private/etc/racoon/stage2");regular("/mnt2/root/procyon/stage3.bin");
    char racoon_backup[65];hash("/mnt2/root/procyon/backup/racoon.conf",racoon_backup);
    if(strcmp(racoon_before,racoon_backup))die("Original racoon configuration backup mismatch");
    equal("/mnt2/root/procyon/backup/backboardd","/mnt1/usr/libexec/backboardd");
    equal("/mnt2/root/procyon/backup/wifiFirmwareLoaderLegacy","/mnt1/usr/libexec/wifiFirmwareLoaderLegacy_orig");
    equal("/mnt2/root/procyon/backup/disabled.plist","/mnt2/db/com.apple.xpc.launchd/disabled_orig.plist");
    char link[2048];ssize_t l=readlink("/mnt1/usr/libexec/wifiFirmwareLoaderLegacy",link,sizeof link-1);
    if(l<=0)die("Missing Wi-Fi boot trigger");link[l]=0;if(strcmp(link,"/usr/sbin/racoon"))die("Unexpected Wi-Fi trigger");
    l=readlink("/mnt1/private/etc/racoon/racoon.conf",link,sizeof link-1);if(l<=0)die("Missing racoon stage link");link[l]=0;
    if(strcmp(link,"/var/root/procyon/stage1/part1.conf"))die("Incorrect stage1 path");
    CFDictionaryRef disabled=plist("/mnt2/db/com.apple.xpc.launchd/disabled.plist");
    if(CFDictionaryGetValue(disabled,CFSTR("com.apple.SpringBoard"))!=kCFBooleanTrue||CFDictionaryGetValue(disabled,CFSTR("com.apple.backboardd"))!=kCFBooleanTrue)die("Service gating missing");
    datafiles(CFDictionaryGetValue(plan,CFSTR("final_data")));
    mkdirs("/mnt2/cache",0,0);writefile("/mnt2/cache/.socket_1_2","",0,0644,0,0);
    mkdirs("/mnt2/mobile/Media/LegacyiOSKitLogs",501,501);
    const char *receipt="Restore-stage untether installation verified. Ordinary boot has not yet been verified.\n";
    writefile("/mnt2/mobile/Media/LegacyiOSKitLogs/restore-install.txt",receipt,strlen(receipt),0644,501,501);
    writefile("/mnt2/root/lik-aio-installed",receipt,strlen(receipt),0600,0,0);
    sync();if(sync_volume_np("/mnt1",0)||sync_volume_np("/mnt2",0))die("Final volume sync");
    line("INSTALLATION_COMPLETE: persistent stages and service gating verified; returning to final unmount");
    return 0;
}
