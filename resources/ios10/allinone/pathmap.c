#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include "pathmap.h"
/* Single-threaded generator; separate slots preserve both rename arguments. */
const char *lik_path(const char *path) {
    static char slots[16][4096]; static unsigned next;
    if (!path || path[0] != '/' || strstr(path, "/../") || strstr(path, "/./") ||
        !strcmp(path, "/..") || (strlen(path)>3 && !strcmp(path+strlen(path)-3,"/.."))) {
        fprintf(stderr,"[LIK-AIO] Invalid generator path\n"); abort();
    }
    const char *root="/mnt1", *tail=path;
    if (!strncmp(path,"/private/var",12) && (!path[12] || path[12]=='/')) {root="/mnt2";tail=path+12;}
    else if (!strncmp(path,"/var",4) && (!path[4] || path[4]=='/')) {root="/mnt2";tail=path+4;}
    else if (!strncmp(path,"/etc",4) && (!path[4] || path[4]=='/')) {root="/mnt1/private/etc";tail=path+4;}
    char *out=slots[next++%16];
    if(snprintf(out,4096,"%s%s",root,tail)>=4096) abort();
    return out;
}
int lik_open(const char *p,int f,...) {mode_t m=0; if(f&O_CREAT){va_list ap;va_start(ap,f);m=va_arg(ap,int);va_end(ap);}return open(lik_path(p),f|O_NOFOLLOW,m);}
int lik_access(const char *p,int m){return access(lik_path(p),m);}
int lik_stat(const char *p,struct stat *s){return stat(lik_path(p),s);}
int lik_lstat(const char *p,struct stat *s){return lstat(lik_path(p),s);}
int lik_mkdir(const char *p,mode_t m){return mkdir(lik_path(p),m);}
int lik_chmod(const char *p,mode_t m){return chmod(lik_path(p),m);}
int lik_chown(const char *p,uid_t u,gid_t g){return chown(lik_path(p),u,g);}
int lik_unlink(const char *p){return unlink(lik_path(p));}
int lik_remove(const char *p){return remove(lik_path(p));}
int lik_rename(const char *a,const char *b){return rename(lik_path(a),lik_path(b));}
int lik_symlink(const char *a,const char *b){return symlink(a,lik_path(b));}
DIR *lik_opendir(const char *p){return opendir(lik_path(p));}
int lik_rmdir(const char *p){return rmdir(lik_path(p));}
int lik_sync_volume_np(const char *p,int f){return sync_volume_np(lik_path(p),f);}
