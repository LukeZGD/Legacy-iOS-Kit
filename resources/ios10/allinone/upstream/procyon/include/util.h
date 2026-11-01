#ifndef procyon_util_h
#define procyon_util_h

#include "common.h"

#define PROC_PIDPATHINFO            11
#define PROC_PIDPATHINFO_SIZE       1024
#define PROC_PIDPATHINFO_MAXSIZE    (4*1024)
#define PROC_ALL_PIDS               1

extern CFDictionaryRef _CFCopySystemVersionDictionary(void);
extern int proc_listpids(uint32_t type, uint32_t typeinfo, void *buffer, int buffersize);
extern int proc_name(int pid, void * buffer, uint32_t buffersize);
extern struct mach_header _mh_execute_header;
extern char **environ;

void *load_file(const char *path, uint32_t *size);
int remove_at_path(const char *path);
int copy_file(const char *from, void *to);
int move_file(const char *from, void *to, bool same_partition);
void sync_path(const char *path);
void sync_volume(const char *path);
void *load_embedded_file(const char *name, size_t *size);
void get_ios_version(uint32_t *output);
void print_log(bool error, const char *fmt, ...);

#endif /* procyon_util_h */
