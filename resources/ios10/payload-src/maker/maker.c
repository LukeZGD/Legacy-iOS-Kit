#include <stdint.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>

//#define PAYLOAD_BASE    0xbfc00000
#define PAYLOAD_BASE    0x80000000

int open_file(char *file, size_t *sz, void **buf){
    FILE *fd = fopen(file, "r");
    if (!fd) {
        printf("error opening %s\n", file);
        return -1;
    }
    
    fseek(fd, 0, SEEK_END);
    *sz = ftell(fd);
    fseek(fd, 0, SEEK_SET);
    
    *buf = malloc(*sz);
    if (!*buf) {
        printf("error allocating file buffer\n");
        fclose(fd);
        return -1;
    }
    
    fread(*buf, *sz, 1, fd);
    fclose(fd);
    
    return 0;
}

int main(int argc, char **argv){
    
    FILE *fd;
    char *p;
    char *pre;
    char *out1;
    char *out2;
    char *out3;
    void *payload;
    void *prehook;
    size_t p_sz;
    size_t pre_sz;
    uint32_t i;
    uint32_t off;
    uint32_t val;
    uint32_t search[4];
    
    if(argc != 6){
        printf("%s <payload> <prehook> <out1> <out2> <out3>\n", argv[0]);
        return 0;
    }
    
    p = argv[1];
    pre = argv[2];
    out1 = argv[3];
    out2 = argv[4];
    out3 = argv[5];
    
    open_file(p, &p_sz, &payload);
    open_file(pre, &pre_sz, &prehook);
    
    search[0] = *(uint32_t*)(payload + 0x0);
    search[1] = *(uint32_t*)(payload + 0x4);
    search[2] = *(uint32_t*)(payload + 0x8);
    search[3] = *(uint32_t*)(payload + 0xc);
    
    i = (uint32_t)memmem(prehook, pre_sz, search, 0x10);
    if(!i){
        printf("failed to get payload head\n");
        return -1;
    }
    i = i-(uint32_t)prehook;
    
    printf("payload: %x\n", i);
    
    val = 0xdeadbeef;
    off = (uint32_t)memmem(prehook, pre_sz, &val, 4);
    if(!off){
        printf("failed to get trampoline\n");
        return -1;
    }
    
    off = off-(uint32_t)prehook;
    
    printf("trampoline: %x\n", off);
    
    *(uint32_t*)(prehook + off) = PAYLOAD_BASE + i;
    
    printf("creating payload1...\n");
    fd = fopen(out1, "w");
    if (!fd) {
        printf("error opening %s\n", out1);
        return -1;
    }
    
    fwrite(prehook, pre_sz, 1, fd);
    fflush(fd);
    fclose(fd);
    
    val = 0xdeadfeed;
    off = (uint32_t)memmem(prehook, pre_sz, &val, 4);
    if(!off){
        printf("failed to get rdsk_boot\n");
        return -1;
    }
    
    off = off-(uint32_t)prehook;
    
    *(uint32_t*)(prehook + off) = 0;
    
    printf("creating payload2...\n");
    fd = fopen(out2, "w");
    if (!fd) {
        printf("error opening %s\n", out2);
        return -1;
    }
    
    fwrite(prehook, pre_sz, 1, fd);
    fflush(fd);
    fclose(fd);
    
    // untether
    val = 0xdeadfeed;
    off = (uint32_t)memmem(payload, p_sz, &val, 4);
    if(!off){
        printf("failed to get rdsk_boot\n");
        return -1;
    }
    
    off = off-(uint32_t)payload;
    
    *(uint32_t*)(payload + off) = 0;
    
    printf("creating payload3...\n");
    fd = fopen(out3, "w");
    if (!fd) {
        printf("error opening %s\n", out3);
        return -1;
    }
    
    fwrite(payload, p_sz, 1, fd);
    fflush(fd);
    fclose(fd);
    
    
    return 0;
}
