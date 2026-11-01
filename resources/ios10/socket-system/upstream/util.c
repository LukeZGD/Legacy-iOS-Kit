//
//  util.c
//  socket
//
//  Created by staturnz on 2/27/26.
//

#include "util.h"


int edit_plist(const char *path, void (^callback)(CFMutableDictionaryRef dict)) {
    int fd = -1;
    uint32_t size = 0;
    void *mapped = NULL;
    CFDataRef data = NULL;
    CFDataRef xml = NULL;
    CFPropertyListRef plist = NULL;
    int status = -1;
    
    if ((fd = open(path, O_RDWR)) < 0) goto done;
    if ((size = (uint32_t)lseek(fd, 0, SEEK_END)) == 0) goto done;
    lseek(fd, 0, SEEK_SET);
    
    CFPropertyListFormat format = kCFPropertyListXMLFormat_v1_0;
    if ((mapped = mmap(NULL, size, PROT_READ, MAP_PRIVATE, fd, 0)) == MAP_FAILED) goto done;
    if (strncmp((char *)mapped, "bplist00", strlen("bplist00")) == 0) format = kCFPropertyListBinaryFormat_v1_0;
    
    if ((data = CFDataCreateWithBytesNoCopy(NULL, mapped, size, kCFAllocatorNull)) == NULL) goto done;
    if ((plist = CFPropertyListCreateWithData(NULL, data, kCFPropertyListMutableContainersAndLeaves, NULL, NULL)) == NULL) goto done;

    callback((CFMutableDictionaryRef)plist);
    if ((xml = CFPropertyListCreateData(NULL, plist, format, 0, NULL)) == NULL) goto done;
    write(fd, CFDataGetBytePtr(xml), CFDataGetLength(xml));
    status = 0;

done:
    if (mapped != NULL && mapped != MAP_FAILED) munmap(mapped, size);
    if (data != NULL) CFRelease(data);
    if (plist != NULL) CFRelease(plist);
    if (xml != NULL) CFRelease(xml);
    if (fd >= 0) close(fd);
    
    sync();
    return status;
}

int run_bin(const char *path, bool wait, int argc, ...) {
    va_list va = NULL;
    va_start(va, argc);
    
    char **args = calloc(1, sizeof(char *) * (argc + 2));
    args[0] = (char *)path;
    for (int i = 0; i < argc; i++) args[i+1] = va_arg(va, char *);
    va_end(va);
    
    pid_t pid = -1;
    int status = -1;
    int rv = posix_spawn(&pid, path, NULL, NULL, args, environ);
    free(args);
    
    if (!wait) return rv;
    do { if (waitpid(pid, &status, 0) == -1) return status; }

    while (!WIFEXITED(status) && !WIFSIGNALED(status));
    return status;
}

int extract_tar(const char *tar_path, const char *output_path) {
    return run_bin("/bin/tar", true, 6, "-xvf", tar_path, "-C", output_path, "--preserve-permissions", "--no-overwrite-dir");
}

int install_deb(const char *deb_path) {
    return run_bin("/usr/bin/dpkg", true, 3, "--force-all", "-i", deb_path);
}

int uicache(void) {
    if (run_bin("/usr/bin/su", true, 3, "mobile", "-c", "/usr/bin/uicache") != 0) {
        return run_bin("/usr/bin/uicache", true, 0, NULL);
    }
    return 0;
}

bool is_jailbroken(void) {
    struct utsname name = {0};
    uname(&name);
    if (strstr(name.version, "MarijuanARM") != NULL) return false;
    
    uint32_t cs_flags = 0;
    uint32_t proc_enforce;
    size_t size = 0x4;
    
    if (access("/", R_OK | W_OK) == 0) return true;
    if (csops(getpid(), CS_OPS_STATUS, &cs_flags, 0x4) == 0) {
        if ((cs_flags & CS_PLATFORM_BINARY) == CS_PLATFORM_BINARY) return true;
    }
    
    if (sysctlbyname("security.mac.proc_enforce", &proc_enforce, &size, NULL, 0) == 0) {
        if (proc_enforce == 0) return true;
    }
    return false;
}

bool file_exists(const char *path) {
    return (access(path, F_OK) == 0);
}

char *bundle_path(const char *item) {
    char exec_path[PATH_MAX] = {0};
    uint32_t size = PATH_MAX-1;
    _NSGetExecutablePath(exec_path, &size);
    
    char *exec_dir = dirname(exec_path);
    if (exec_dir == NULL) return NULL;
    
    char path_buf[PATH_MAX] = {0};
    snprintf(path_buf, PATH_MAX-1, "%s/%s", exec_dir, item);
    return strdup(path_buf);
}

void *map_file(const char *path, uint32_t *size) {
    int fd = open(path, O_RDONLY);
    if (fd == -1) return NULL;

    *size = (uint32_t)lseek(fd, 0, SEEK_END);
    lseek(fd, 0, SEEK_SET);

    void *data = mmap(NULL, *size, PROT_READ, MAP_PRIVATE, fd, 0);
    close(fd);

    if (data == MAP_FAILED) {
        *size = 0;
        return NULL;
    }
    return data;
}

void *map_bundle_file(const char *name, uint32_t *size) {
    char *path = bundle_path(name);
    if (path == NULL) return NULL;
    
    void *data = map_file(path, size);
    free(path);
    return data;
}

void unmap_file(void *data, uint32_t size) {
    if (data == NULL || size == 0) return;
    munmap(data, size);
}

void flush_file(int fd) {
    if (fd < 0) return;
    fsync(fd);
    fcntl(fd, F_FULLFSYNC);
    usleep(100);
    sync();
}

void flush_volume(const char *path) {
    sync_volume_np(path, 0);
    usleep(100);
    sync();
}

int create_dotfile(const char *path) {
    if (access(path, F_OK) == 0) return 0;
    int fd = open(path, O_RDWR | O_CREAT | O_TRUNC);
    if (fd < 0) return -1;
    
    close(fd);
    chmod(path, 0644);
    chown(path, 0, 0);
    return 0;
}

uint32_t get_file_size(const char *path) {
    if (access(path, F_OK) == 0) return 0;
    
    struct stat st = {0};
    if (stat(path, &st) != 0) return 0;
    return (uint32_t)st.st_size;
}

int copy_file(const char *src, const char *dest, mode_t mode, uid_t uid, gid_t gid) {
    uint32_t size = 0;
    void *data = map_file(src, &size);
    if (data == NULL) return -1;
    
    int fd = open(dest, O_RDWR | O_CREAT | O_TRUNC);
    if (fd < 0) {
        unmap_file(data, size);
        return -1;
    }
    
    write(fd, data, size);
    flush_file(fd);
    close(fd);
    
    unmap_file(data, size);
    chmod(dest, mode);
    chown(dest, uid, gid);
    return 0;
}

int copy_bundle_file(const char *name, const char *dest, mode_t mode, uid_t uid, gid_t gid) {
    char *src = bundle_path(name);
    if (src == NULL) return -1;
 
    int rv = copy_file(src, dest, mode, uid, gid);
    free(src);
    return rv;
}

int move_file(const char *src, const char *dest) {
    unlink(dest);
    if (rename(src, dest) == 0) return 0;
    
    struct stat st = {0};
    if (stat(src, &st) != 0) return -1;
    
    int rv = copy_file(src, dest, st.st_mode, st.st_uid, st.st_gid);
    unlink(src);
    return rv;
}

int remove_at_path(const char *path) {
    if (access(path, F_OK) != 0) return 0;
    struct stat st = {0};
    int rv = 0;

    if (lstat(path, &st) == 0) {
        if (S_ISDIR(st.st_mode)) {
            DIR *dir = opendir(path);
            if (dir == NULL) return -1;
            struct dirent *entry = NULL;
                
            while (rv == 0 && (entry = readdir(dir))) {
                char *item = (char *)entry->d_name;
                if (strcmp(item, ".") == 0 || strcmp(item, "..") == 0) continue;
                
                size_t path_len = strlen(path) + strlen(item) + 2;
                char *path_buf = calloc(1, path_len);
                if (path_buf == NULL) continue;
                
                bzero(&st, sizeof(struct stat));
                snprintf(path_buf, path_len, "%s/%s", path, item);
                    
                if (lstat(path_buf, &st) == 0) {
                    if (S_ISDIR(st.st_mode)) {
                        rv = remove_at_path(path_buf);
                    } else {
                        rv = unlink(path_buf);
                    }
                }
                free(path_buf);
            }
            
            closedir(dir);
            if (rv == 0) rv = rmdir(path);
            return rv;
        }

        rv = unlink(path);
        if (rv != 0 || access(path, F_OK) == 0) rv = remove(path);
        return rv;
    }
    return -1;
}

int iterate_dir(const char *path, const char *pattern, void (^callback)(char *path)) {
    DIR *dir = opendir(path);
    if (dir == NULL) return -1;
    
    struct dirent *entry = NULL;
    char *full_path = calloc(1, PATH_MAX);
    
    while ((entry = readdir(dir)) != NULL) {
        char *item = (char *)entry->d_name;
        if (strcmp(item, ".") == 0 || strcmp(item, "..") == 0) continue;
        
        if (pattern == NULL || fnmatch(pattern, path, 0) == 0) {
            bzero(full_path, PATH_MAX);
            snprintf(full_path, PATH_MAX-1, path, item);
            callback(full_path);
        }
    }
    
    free(full_path);
    return 0;
}
