/* Restore-only filesystem adapter. Payload strings remain normal iOS paths. */
#ifndef LIK_PATHMAP_H
#define LIK_PATHMAP_H
#include <sys/stat.h>
#include <dirent.h>
const char *lik_path(const char *path);
int lik_open(const char *, int, ...);
int lik_access(const char *, int);
int lik_stat(const char *, struct stat *);
int lik_lstat(const char *, struct stat *);
int lik_mkdir(const char *, mode_t);
int lik_chmod(const char *, mode_t);
int lik_chown(const char *, uid_t, gid_t);
int lik_unlink(const char *);
int lik_remove(const char *);
int lik_rename(const char *, const char *);
int lik_symlink(const char *, const char *);
DIR *lik_opendir(const char *);
int lik_rmdir(const char *);
int lik_sync_volume_np(const char *, int);
#ifdef LIK_MAP_CALLS
#define open lik_open
#define access lik_access
#define stat(...) lik_stat(__VA_ARGS__)
#define lstat lik_lstat
#define mkdir lik_mkdir
#define chmod lik_chmod
#define chown lik_chown
#define unlink lik_unlink
#define remove lik_remove
#define rename lik_rename
#define symlink lik_symlink
#define opendir lik_opendir
#define rmdir lik_rmdir
#define sync_volume_np lik_sync_volume_np
#endif
#endif
