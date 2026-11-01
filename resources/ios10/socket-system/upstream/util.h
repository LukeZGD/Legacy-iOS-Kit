//
//  util.h
//  socket
//
//  Created by staturnz on 2/27/26.
//

#ifndef socket_util_h
#define socket_util_h

#include <stdio.h>
#include <stdlib.h>
#include <stdbool.h>
#include <unistd.h>
#include <sys/mman.h>
#include <sys/file.h>
#include <sys/stat.h>
#include <sys/sysctl.h>
#include <sys/utsname.h>
#include <sys/mount.h>
#include <spawn.h>
#include <sys/dir.h>
#include <sys/dirent.h>
#include <libgen.h>
#include <glob.h>
#include <fnmatch.h>
#include <CoreFoundation/CoreFoundation.h>

#define CS_TYPE_ENTS        0x00000005
#define CS_OPS_STATUS       0x00000000
#define CS_PLATFORM_BINARY  0x04000000

extern char **environ;
extern int csops(pid_t pid, unsigned int  ops, void * useraddr, size_t usersize);

int edit_plist(const char *path, void (^callback)(CFMutableDictionaryRef dict));
int run_bin(const char *path, bool wait, int argc, ...);
int extract_tar(const char *tar_path, const char *output_path);
int install_deb(const char *deb_path);
int uicache(void);
bool is_jailbroken(void);
bool file_exists(const char *path);
char *bundle_path(const char *item);
void *map_file(const char *path, uint32_t *size);
void *map_bundle_file(const char *name, uint32_t *size);
void unmap_file(void *data, uint32_t size);
void flush_file(int fd);
void flush_volume(const char *path);
int create_dotfile(const char *path);
uint32_t get_file_size(const char *path);
int copy_file(const char *src, const char *dest, mode_t mode, uid_t uid, gid_t gid);
int copy_bundle_file(const char *name, const char *dest, mode_t mode, uid_t uid, gid_t gid);
int move_file(const char *src, const char *dest);
int remove_at_path(const char *path);
int iterate_dir(const char *path, const char *pattern, void (^callback)(char *path));


#endif /* socket_util_h */
