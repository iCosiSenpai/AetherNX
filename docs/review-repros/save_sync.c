#include <stdio.h>
#include <dirent.h>
#include <errno.h>
#include <stdatomic.h>
#include <assert.h>
static int fail_backup_rename, deny_scan;
static char denied_path[4096];
static int review_rename(const char *, const char *);
static DIR *review_opendir(const char *);
#define rename review_rename
#define opendir review_opendir
#include "../../dm/host/save_sync.c"
#undef rename
#undef opendir
_Atomic int review_fetch_mode, review_fetch_ready, review_fetch_release;
static int review_rename(const char *a, const char *b) {
    if (fail_backup_rename && strstr(b, "-backups/") && strstr(b, "/save")) { errno=ENOSPC; return -1; }
    return rename(a,b);
}
static DIR *review_opendir(const char *p) {
    if (deny_scan && !strcmp(p,denied_path)) { errno=EACCES; return NULL; }
    return opendir(p);
}
static void put_text(const char *p,const char *s) { FILE *f=fopen(p,"w"); assert(f); assert(fputs(s,f)>=0); assert(!fclose(f)); }
static int text_is(const char *p,const char *s) { char b[100]={0}; FILE *f=fopen(p,"r"); if(!f)return 0; fread(b,1,99,f); fclose(f); return !strcmp(b,s); }
int main(int argc,char **argv) {
    assert(argc==2);
    char root[]="/private/tmp/horizonnative-code-review/savecase.XXXXXX";
    assert(mkdtemp(root));
    char save[4096],file[4096],other[4096],of[4096],bundle[4096],kept[4096],tmp[4096];
    snprintf(save,sizeof save,"%s/local/save",root); assert(!mkdirs(save));
    snprintf(file,sizeof file,"%s/progress",save); put_text(file,"LOCAL");
    ss_meta m;
    if(!strcmp(argv[1],"scan")) {
        snprintf(denied_path,sizeof denied_path,"%s",save); deny_scan=1;
        int status=ss_scan(save,&m);
        printf("Unreadable save scan: status=%d files=%u hash_empty=%d (expected error)\n",status,m.files,!m.hash[0]);
        assert(status==0 && m.files==0 && !m.hash[0]);
        deny_scan=0;
    } else if(!strcmp(argv[1],"pull")) {
        snprintf(other,sizeof other,"%s/remote/save",root); assert(!mkdirs(other));
        snprintf(of,sizeof of,"%s/progress",other); put_text(of,"REMOTE");
        snprintf(bundle,sizeof bundle,"%s/remote.dmsync",root); assert(!ss_pack(other,"0100ABC",bundle,&m));
        fail_backup_rename=1; int status=pull(save,bundle,&m,kept,sizeof kept); fail_backup_rename=0;
        snprintf(tmp,sizeof tmp,"%s.sync-tmp",save); assert(!rm_tree(tmp));
        printf("Backup rename failure: pull=%d active_is_LOCAL=%d active_is_REMOTE=%d backup_empty=%d\n",status,text_is(file,"LOCAL"),text_is(file,"REMOTE"),!has_entries(kept));
        assert(status==-1 && text_is(file,"REMOTE") && !has_entries(kept));
    } else {
        snprintf(file,sizeof file,"%s/download",root); atomic_store(&review_fetch_mode,1);
        assert(fetch_timed("unused",file,20)==-1);
        for(int i=0;i<1000 && !atomic_load(&review_fetch_ready);i++)usleep(1000);
        assert(atomic_load(&review_fetch_ready));
        put_text(file,"NEW_DOWNLOAD"); assert(!access(file,F_OK));
        atomic_store(&review_fetch_release,1);
        for(int i=0;i<1000 && !access(file,F_OK);i++)usleep(1000);
        printf("Abandoned fetch cleanup removed newer download: %d\n",access(file,F_OK)!=0);
        assert(access(file,F_OK)!=0);
    }
    rm_tree(root); return 0;
}
