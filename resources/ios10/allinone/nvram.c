/* Only the restore ramdisk uses this wrapper; installed nvram is untouched. */
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <sys/wait.h>
#include <errno.h>
static int run(char *const argv[]) {
    pid_t p=fork(); if(p<0)return 125;
    if(!p){execv(argv[0],argv);_exit(126);}
    int s;while(waitpid(p,&s,0)<0){if(errno!=EINTR)return 125;}
    return WIFEXITED(s)?WEXITSTATUS(s):128+WTERMSIG(s);
}
int main(int argc,char **argv) {
    int trigger=argc==2 && !strcmp(argv[1],"bootdelay=0");
    argv[0]="/usr/sbin/nvram.stock";
    int result=run(argv);if(result || !trigger)return result;
    puts("[LIK-AIO] FINAL_MOUNTED_STAGE: starting installation before final unmount");fflush(stdout);
    char *install[]={"/usr/local/bin/lik-restore-finalize",NULL};
    result=run(install);
    if(result){
        fprintf(stderr,"[LIK-AIO] INSTALLATION_FAILED exit=%d; keeping recovery boot enabled\n",result);
        char *recovery[]={"/usr/sbin/nvram.stock","auto-boot=false",NULL};run(recovery);
    }
    return result;
}
