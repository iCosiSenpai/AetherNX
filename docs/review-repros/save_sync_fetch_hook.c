#include <stdio.h>
#include <assert.h>
#include <stdatomic.h>
#include <unistd.h>
extern _Atomic int review_fetch_mode,review_fetch_ready,review_fetch_release;
int front_save_sync_fetch(const char *cloud,const char *local) {
    (void)cloud;
    FILE *f=fopen(local,"w");assert(f);fputs("OLD_DOWNLOAD",f);fclose(f);
    atomic_store(&review_fetch_ready,1);
    while(!atomic_load(&review_fetch_release))usleep(1000);
    return 1;
}
