#include "procyon.h"
#include "util.h"

void *load_file(const char *path, uint32_t *size) {
    int fd = open(path, O_RDONLY);
    if (fd < 0) return NULL;
    
    *size = (uint32_t)lseek(fd, 0, SEEK_END);
    lseek(fd, 0, SEEK_SET);

    void *data = mmap(NULL, *size, PROT_READ|PROT_WRITE, MAP_PRIVATE, fd, 0);
    close(fd);

    if (data == MAP_FAILED) {
        *size = 0;
        return NULL;
    }
    return data;
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
                if (strcmp(item, ".") == 0)  continue;
                if (strcmp(item, "..") == 0)  continue;
                
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

int copy_file(const char *from, void *to) {
    struct stat st = {0};
    if (stat(from, &st) != 0) return -1;

    uint32_t size = 0;
    void *data = load_file(from, &size);
    if (data == NULL) return -1;

    if (access(to, F_OK) == 0) {
        remove_at_path(to);
    }

    int fd = open(to, O_RDWR|O_CREAT);
    if (fd < 0) {
        munmap(data, size);
        return -1;
    }

    write(fd, data, size);
    close(fd);
    sync();

    munmap(data, size);
    chmod(to, st.st_mode);
    chown(to, st.st_uid, st.st_gid);
    return 0;
}

int move_file(const char *from, void *to, bool same_partition) {
    if (same_partition) return rename(from, to);
    if (copy_file(from, to) != 0) return -1;

    remove_at_path(from);
    return 0;
}

void sync_path(const char *path) {
    struct stat st = {0};
    if (stat(path, &st) == -1) return;
    int fd = -1;

    if (S_ISDIR(st.st_mode)) {
        fd = open(path, O_RDONLY | O_DIRECTORY);
        if (fd < 0) return;
        fsync(fd);
    } else {
        fd = open(path, O_RDONLY);
        if (fd < 0) return;

        if (fcntl(fd, F_FULLFSYNC) == -1) {
            fsync(fd);
        }
    }
    close(fd);
}

void sync_volume(const char *path) {
    int fd = open(path, O_RDONLY | O_DIRECTORY);
    if (fd >= 0) {
        fsync(fd);
        close(fd);
    }

    usleep(10000);
    sync();

    usleep(10000);
    sync_volume_np(path, 0);
}

void *load_embedded_file(const char *name, size_t *size) {
    struct mach_header *hdr = &_mh_execute_header;
    struct load_command *load_cmd = (struct load_command *)(hdr + 1);

    for (int i = 0; i < hdr->ncmds; i++) {
        if (load_cmd->cmd == LC_SEGMENT) {
            struct segment_command *segment = (struct segment_command *)load_cmd;
            if (strcmp(segment->segname, "__DATA") == 0) {
                struct section *section = (struct section *)(segment + 1);

                for (uint32_t j = 0; j < segment->nsects; j++) {
                    if (strcmp(section->sectname, name) == 0) {
                        *size = section->size;
                        return (void *)((uint8_t *)hdr + section->offset);
                    }
                    section++;
                }
            }
        }
        load_cmd = (struct load_command *)((uint64_t)load_cmd + load_cmd->cmdsize);
    }
    return NULL;
}

void killall(const char *process_name) {
    int count = proc_listpids(PROC_ALL_PIDS, 0, NULL, 0) + 100;
    if (count <= 0) return;

    pid_t *pids = calloc(1, sizeof(pid_t) * count);
    count = proc_listpids(PROC_ALL_PIDS, 0, pids, sizeof(pid_t) * count);
    if (count <= 0) {
        free(pids);
        return;
    }

    char *name = calloc(1, PROC_PIDPATHINFO_MAXSIZE+1);
    for (int i = 0; i < count; i++) {
        bzero(name, PROC_PIDPATHINFO_MAXSIZE+1);
        pid_t pid = pids[i];

        if (proc_name(pid, name, PROC_PIDPATHINFO_MAXSIZE) <= 0) continue;
        if (strncmp((const char *)name, process_name, PROC_PIDPATHINFO_MAXSIZE) == 0) {
            if (pid != getpid()) {
                kill(pid, SIGKILL);
            }
        }
    }

    free(name);
    free(pids);
}

void get_ios_version(uint32_t *output) {
    char str[32] = {0};
    CFDictionaryRef dict = _CFCopySystemVersionDictionary();
    CFStringRef version = CFDictionaryGetValue(dict, CFSTR("ProductVersion"));
    CFStringGetCString(version, str, 32, kCFStringEncodingUTF8);
    
    sscanf(str, "%d.%d.%d", &output[0], &output[1], &output[2]);
    CFRelease(dict);
}

void print_log(bool error, const char *fmt, ...) {
    FILE *file = error ? stderr : stdout;
    va_list va = NULL;
    va_start(va, fmt);
    vfprintf(file, fmt, va);
    va_end(va);

    fflush(file);
    usleep(0);
}
