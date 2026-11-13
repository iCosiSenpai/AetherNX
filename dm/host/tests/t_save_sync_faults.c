// Cloud save sync under failures (takes about a second): dm/host/save_sync.c with its folder reads, renames and attribute reads replaced by hooks that fail on cue,
// and the platform's fetch replaced by t_save_sync_faults_hook.c. No cloud provider, game or player save is used: every folder is a synthetic one under TMPDIR.
// Each case states the rule from save_sync.h / docs/code-review.md it checks:
//   (1) a save folder that cannot be read (opendir, a listing that fails part way, a guest-name attribute) is an error, never an empty save
//   (2) a pull that goes through: the cloud's save in place, this device's in the backup, nothing left beside the save, and only then old backups pruned
//   (3) a pull whose N-th move fails (each of the four in turn): this device's save is back as it was, no backup is left and no old backup was pruned
//   (4) a pull whose move fails and whose putting back fails too: -2, this device's save is whole between its place and the backup (never in <save>.sync-tmp), and the
//       journal (<save>.pull) that stays puts it back once the moves work again
//   (5) an empty folder (only .DS_Store) in the way is swapped out, and an empty folder is there again when the pull fails (Finder's file is no save)
//   (6) a folder of this device that cannot be read stops the pull before anything moves
//   (7) the first mount: a failed pull leaves this device's save and its sync state; (8) a save that cannot be read turns sync off rather than bring the cloud's in
//   (9) a fetch abandoned at its time limit removes only its own download, never a later one at the same path; (10) one in time is published at its path
//   (11) a send with a folder that cannot be read sends nothing
//   (12) a send when both changed sends nothing, whichever is newer: the next start decides (also for the Mac launcher after a host that never mounted); once a start chose
//        this device's save, the send replaces the cloud save it chose against
//   (13) a cloud backup that cannot be completed (at the start that chose this device's save) is removed, costs no older backup, and nothing is sent
//   (14) the sync state belongs to one cloud file: another folder chosen gets the save even if it did not change; a state file from before the cloud line still counts
//   (15) a pull that could not be put back refuses the mount, the Mac launcher's send sends nothing while its journal is pending, and the next start puts the save back
//   (16) a send whose upload fails keeps no extra cloud backup and prunes none (the damaged cloud file, the one cloud save a send keeps and replaces by itself)
//   (17) a pull stopped between its moves (the app ended at each of the four): its journal is already on disk, the Mac launcher's send sends nothing, and the next start
//        puts this device's save back whole (sync on or off); a pull that ends whole, either way, leaves no journal ((2), (3), (5), (6))
#include <dirent.h>
#include <errno.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <sys/xattr.h>
#include <unistd.h>

static int hook_on, hook_calls, hook_fail_at[4], hook_nfail, hook_end_at;   // moves (rename, renamex_np) counted while hook_on; the hook_fail_at-th ones fail with ENOSPC,
                                                                            // and at the hook_end_at-th one the process ends before it moves (exit status 9)
static char deny_dir[4096], eio_dir[4096], erange_file[4096], deny_setxattr_in[4096];
static DIR *eio_handle; static int eio_reads;
static int hook_move_fails(const char *a) {
    if (!hook_on || strstr(a, ".part") || strstr(a, ".pull.tmp")) return 0;   // a fetch's own file going to its place, and the pull's journal, are not the pull's moves
    hook_calls++;
    if (hook_end_at == hook_calls) _exit(9);
    for (int i = 0; i < hook_nfail; i++) if (hook_fail_at[i] == hook_calls) { errno = ENOSPC; return 1; }
    return 0;
}
static int hook_rename(const char *a, const char *b) { return hook_move_fails(a) ? -1 : rename(a, b); }
static int hook_renamex_np(const char *a, const char *b, unsigned f) { return hook_move_fails(a) ? -1 : renamex_np(a, b, f); }
static DIR *hook_opendir(const char *p) {
    if (*deny_dir && !strcmp(p, deny_dir)) { errno = EACCES; return NULL; }
    DIR *d = opendir(p);
    if (d && *eio_dir && !strcmp(p, eio_dir)) { eio_handle = d; eio_reads = 0; }
    return d;
}
static struct dirent *hook_readdir(DIR *d) {
    if (d == eio_handle && eio_reads++ >= 2) { errno = EIO; return NULL; }   // ".", "..", then the device fails
    return readdir(d);
}
static int hook_closedir(DIR *d) { if (d == eio_handle) eio_handle = NULL; return closedir(d); }
static ssize_t hook_getxattr(const char *p, const char *n, void *v, size_t s, uint32_t pos, int o) {
    if (*erange_file && !strcmp(p, erange_file)) { errno = ERANGE; return -1; }
    return getxattr(p, n, v, s, pos, o);
}
static int hook_setxattr(const char *p, const char *n, const void *v, size_t s, uint32_t pos, int o) {
    if (*deny_setxattr_in && strstr(p, deny_setxattr_in)) { errno = ENOSPC; return -1; }
    return setxattr(p, n, v, s, pos, o);
}
#define rename hook_rename
#define renamex_np hook_renamex_np
#define opendir hook_opendir
#define readdir hook_readdir
#define closedir hook_closedir
#define getxattr hook_getxattr
#define setxattr hook_setxattr
#include "../save_sync.c"
#undef rename
#undef renamex_np
#undef opendir
#undef readdir
#undef closedir
#undef getxattr
#undef setxattr

extern _Atomic int hook_fetch_mode, hook_fetch_ready, hook_fetch_release, hook_fetch_calls;
extern char hook_fetch_dest[4096];

static int fails, checks;
#define CHECK(c, ...) do { checks++; if (!(c)) { fails++; printf("  ✗ "); } else printf("  ✓ "); printf(__VA_ARGS__); printf("\n"); fflush(stdout); } while (0)
static char root[1024];
static void put(const char *p, const char *s) { FILE *f = fopen(p, "w"); if (f) { fputs(s, f); fclose(f); } }
static int same(const char *p, const char *s) {
    char b[64] = {0}; FILE *f = fopen(p, "r"); if (!f) return 0; size_t k = fread(b, 1, sizeof b - 1, f); fclose(f);
    return k == strlen(s) && !memcmp(b, s, k);
}
static int exists(const char *p) { return !access(p, F_OK); }
static void hooks_off(void) { hook_on = hook_calls = hook_nfail = hook_end_at = 0; deny_dir[0] = eio_dir[0] = erange_file[0] = deny_setxattr_in[0] = 0; }
static void fail_moves(int a, int b) { hooks_off(); hook_on = 1; hook_fail_at[hook_nfail++] = a; if (b) hook_fail_at[hook_nfail++] = b; }
static int count_dirs(const char *dir, const char *suffix) {
    int n = 0; DIR *d = opendir(dir); struct dirent *e; size_t sl = strlen(suffix);
    while (d && (e = readdir(d))) { size_t l = strlen(e->d_name); n += e->d_name[0] != '.' && l > sl && !strcmp(e->d_name + l - sl, suffix); }
    if (d) closedir(d); return n;
}

// A device's save (save/progress, save_device/island) and a cloud bundle of another (REMOTE values), in a folder of their own for each case
typedef struct { char dir[1200], save[1300], dev[1300], prog[1400], isl[1400], bundle[1400], cloud[1300], cfile[1400]; } fixture;
static void backup_of_side(const char *save, const char *side, char *out, size_t n) {   // the newest backup of that side, "" for none
    char dir[1400], best[256] = ""; snprintf(dir, sizeof dir, "%s-backups", save); out[0] = 0;
    DIR *d = opendir(dir); struct dirent *e; size_t sl = strlen(side);
    while (d && (e = readdir(d))) { size_t l = strlen(e->d_name); if (l > sl && e->d_name[l - sl - 1] == ' ' && !strcmp(e->d_name + l - sl, side) && strcmp(e->d_name, best) > 0) strlcpy(best, e->d_name, sizeof best); }
    if (d) closedir(d);
    if (*best) snprintf(out, n, "%s/%s", dir, best);
}
static void make_fixture(fixture *f, const char *name, int device) {
    snprintf(f->dir, sizeof f->dir, "%s/%s", root, name);
    snprintf(f->save, sizeof f->save, "%s/local/save", f->dir); snprintf(f->dev, sizeof f->dev, "%s_device", f->save);
    snprintf(f->prog, sizeof f->prog, "%s/progress", f->save); snprintf(f->isl, sizeof f->isl, "%s/island", f->dev);
    mkdirs(f->save); put(f->prog, "LOCAL");
    if (device) { mkdirs(f->dev); put(f->isl, "LOCAL_ISLAND"); }
    char remote[1300], rdev[1300], p[1400]; ss_meta m;
    snprintf(remote, sizeof remote, "%s/remote/save", f->dir); snprintf(rdev, sizeof rdev, "%s_device", remote);
    mkdirs(remote); snprintf(p, sizeof p, "%s/progress", remote); put(p, "REMOTE");
    mkdirs(rdev); snprintf(p, sizeof p, "%s/island", rdev); put(p, "REMOTE_ISLAND");
    snprintf(f->cloud, sizeof f->cloud, "%s/cloud", f->dir); snprintf(f->cfile, sizeof f->cfile, "%s/0100ABC/save.dmsync", f->cloud);
    snprintf(p, sizeof p, "%s/0100ABC", f->cloud); mkdirs(p);
    ss_pack(remote, "0100abc", f->cfile, &m);
    snprintf(f->bundle, sizeof f->bundle, "%s", f->cfile);
}
static void set_mtime(const char *p, time_t t) { struct timespec ts[2] = {{t, 0}, {t, 0}}; utimensat(AT_FDCWD, p, ts, 0); }
static int cloud_value(const char *bundle, const char *value) {   // the cloud file's save/progress
    static int k; char into[1400], p[1500]; ss_meta m;
    snprintf(into, sizeof into, "%s/peek%d", root, k++); mkdirs(into);
    if (ss_read(bundle, into, &m)) return 0;
    snprintf(p, sizeof p, "%s/save/progress", into); return same(p, value);
}
static int unchanged(const char *p, const struct stat *was) { struct stat st; return !stat(p, &st) && st.st_ino == was->st_ino && st.st_size == was->st_size && st.st_mtimespec.tv_sec == was->st_mtimespec.tv_sec && st.st_mtimespec.tv_nsec == was->st_mtimespec.tv_nsec; }
static int local_intact(const fixture *f, int device) { return same(f->prog, "LOCAL") && (!device || same(f->isl, "LOCAL_ISLAND")); }
static int marked(const fixture *f) { char p[1400]; snprintf(p, sizeof p, "%s.pull", f->save); return exists(p); }   // a pull's journal is pending

int main(void) {
    const char *sp = getenv("TMPDIR"); snprintf(root, sizeof root, "%s/t_save_sync_faults.XXXXXX", sp ? sp : "/private/tmp");
    if (!mkdtemp(root)) { perror("mkdtemp"); return 1; }
    char p[1500], q[1500], kept[1400]; ss_meta m;

    printf("(1) a save that cannot be read is not an empty save\n");
    {   fixture f; make_fixture(&f, "scan", 1);
        hooks_off(); snprintf(deny_dir, sizeof deny_dir, "%s", f.save);
        CHECK(ss_scan(f.save, &m) == -1, "the save folder refuses to open (EACCES): the scan fails");
        hooks_off(); snprintf(deny_dir, sizeof deny_dir, "%s", f.dev);
        CHECK(ss_scan(f.save, &m) == -1, "the device save folder refuses to open: the scan fails");
        hooks_off(); snprintf(eio_dir, sizeof eio_dir, "%s", f.save);
        CHECK(ss_scan(f.save, &m) == -1, "the listing fails part way (EIO): the scan fails rather than see a shorter save");
        hooks_off(); snprintf(erange_file, sizeof erange_file, "%s", f.prog);
        CHECK(ss_scan(f.save, &m) == -1, "a file's guest name cannot be read: the scan fails rather than pack it under another name");
        hooks_off();
        CHECK(!ss_scan(f.save, &m) && m.files == 2, "readable again: 2 files (%d)", m.files);
        snprintf(p, sizeof p, "%s/none/save", root);
        CHECK(!ss_scan(p, &m) && !m.files && !m.hash[0], "no save folder at all is still no save");
    }

    printf("(2) a pull that goes through\n");
    {   fixture f; make_fixture(&f, "pull_ok", 1);
        snprintf(q, sizeof q, "%s-backups", f.save);
        for (int i = 0; i < KEEP_BACKUPS; i++) { snprintf(p, sizeof p, "%s/2001-01-01 00.00.%02d local", q, i); mkdirs(p); }
        hooks_off();
        CHECK(pull(f.save, f.bundle, &m, kept, sizeof kept) == 0, "pull: 0");
        CHECK(same(f.prog, "REMOTE") && same(f.isl, "REMOTE_ISLAND"), "the cloud's save is in place, both folders");
        snprintf(p, sizeof p, "%s/save/progress", kept); snprintf(q, sizeof q, "%s/save_device/island", kept);
        CHECK(*kept && same(p, "LOCAL") && same(q, "LOCAL_ISLAND"), "this device's is in the backup (%s)", kept);
        snprintf(p, sizeof p, "%s.sync-tmp/in", f.save); CHECK(!exists(p), "nothing is left beside the save");
        CHECK(!marked(&f), "and no %s.pull: the pull ended whole", f.save);
        snprintf(q, sizeof q, "%s-backups", f.save); snprintf(p, sizeof p, "%s/2001-01-01 00.00.00 local", q);
        CHECK(count_dirs(q, " local") == KEEP_BACKUPS && !exists(p), "the oldest backup went once the pull went through (%d stay)", count_dirs(q, " local"));
    }

    printf("(3) a pull whose move fails is put back\n");
    for (int at = 1; at <= 4; at++) {
        char name[32]; snprintf(name, sizeof name, "pull_fail%d", at);
        fixture f; make_fixture(&f, name, 1);
        snprintf(q, sizeof q, "%s-backups", f.save);
        for (int i = 0; i < KEEP_BACKUPS; i++) { snprintf(p, sizeof p, "%s/2001-01-01 00.00.%02d local", q, i); mkdirs(p); }
        fail_moves(at, 0);
        int r = pull(f.save, f.bundle, &m, kept, sizeof kept);
        hooks_off();
        snprintf(p, sizeof p, "%s.sync-tmp/in", f.save);
        CHECK(r == -1 && local_intact(&f, 1) && !*kept && !exists(p) && !marked(&f), "move %d of 4 fails: -1, this device's save as it was, nothing beside it, no journal (%d)", at, r);
        CHECK(count_dirs(q, " local") == KEEP_BACKUPS, "and no backup was made or pruned (%d)", count_dirs(q, " local"));
    }

    printf("(4) a failed pull that cannot be put back keeps this device's save whole\n");
    {   fixture f; make_fixture(&f, "pull_stuck", 1);
        fail_moves(3, 4);   // the device folder's move to the backup fails, and so does taking the cloud's save folder back out of the way
        int r = pull(f.save, f.bundle, &m, kept, sizeof kept);
        hooks_off();
        snprintf(p, sizeof p, "%s/save/progress", kept);
        CHECK(r == -2 && *kept && same(p, "LOCAL") && same(f.isl, "LOCAL_ISLAND"), "-2: this device's save folder is in the backup, its device folder in place (%d)", r);
        snprintf(p, sizeof p, "%s.sync-tmp", f.save);
        CHECK(!exists(p) || count_dirs(p, "") == 0, "nothing of this device's is left in <save>.sync-tmp");
        pull_journal j; snprintf(q, sizeof q, "%s", kept);
        CHECK(marked(&f) && journal_read(f.save, &j) == 1 && !strcmp(j.kept, q), "%s.pull stays and names that backup (%s)", f.save, j.kept);
        CHECK(recover(f.save, &j) == 0 && local_intact(&f, 1) && !marked(&f) && !exists(q), "with the moves working again it puts this device's save back, the journal and the backup gone");
    }

    printf("(5) an empty folder in the way\n");
    {   fixture f; make_fixture(&f, "pull_empty", 0);
        unlink(f.prog); snprintf(p, sizeof p, "%s/.DS_Store", f.save); put(p, "finder");
        fail_moves(2, 0);   // swap of the save folder, then the device folder's move in fails
        int r = pull(f.save, f.bundle, &m, kept, sizeof kept);
        hooks_off();
        CHECK(r == -1 && exists(f.save) && !has_entries(f.save) && !exists(f.prog) && !exists(f.dev) && !*kept && !marked(&f), "put back: an empty save folder, no cloud file, no backup, no journal (%d)", r);
        CHECK(pull(f.save, f.bundle, &m, kept, sizeof kept) == 0 && same(f.prog, "REMOTE") && !*kept && !marked(&f), "without the failure the cloud's comes in, with no backup of an empty folder");
    }

    printf("(6) a folder that cannot be read stops the pull\n");
    {   fixture f; make_fixture(&f, "pull_unreadable", 1);
        hooks_off(); hook_on = 1; snprintf(deny_dir, sizeof deny_dir, "%s", f.dev);
        int r = pull(f.save, f.bundle, &m, kept, sizeof kept), moved = hook_calls;
        hooks_off();
        snprintf(q, sizeof q, "%s-backups", f.save);
        CHECK(r == -1 && !moved && local_intact(&f, 1) && !exists(q) && !marked(&f), "-1 before any move, and no backup folder or journal (%d, %d moves)", r, moved);
    }

    printf("(7) the first mount, with a pull that fails\n");
    {   fixture f; make_fixture(&f, "mount_fail", 1);
        ss_meta mine; ss_scan(f.save, &mine); write_base(f.save, f.cfile, mine.hash);   // in step before: only the cloud's changed, so the mount pulls
        char base_before[SS_HASH + 1], base_after[SS_HASH + 1]; read_base(f.save, f.cfile, base_before);
        fflush(stdout); pid_t c = fork();
        if (!c) {
            setenv("DM_SAVE_SYNC", f.cloud, 1); fail_moves(2, 0);
            save_sync_mount(f.save, "0100abc");
            _exit(hook_calls >= 2 ? 0 : 3);
        }
        int st; waitpid(c, &st, 0);
        read_base(f.save, f.cfile, base_after);
        CHECK(WIFEXITED(st) && !WEXITSTATUS(st), "the mount pulled and its second move failed");
        CHECK(local_intact(&f, 1) && !strcmp(base_before, base_after), "this device's save and its sync state are as they were");
        snprintf(p, sizeof p, "%s.sync-tmp", f.save); CHECK(!exists(p) || count_dirs(p, "") == 0, "nothing is left beside the save");
    }

    printf("(8) the first mount, with a save that cannot be read\n");
    {   fixture f; make_fixture(&f, "mount_unreadable", 1);
        fflush(stdout); pid_t c = fork();
        if (!c) {
            setenv("DM_SAVE_SYNC", f.cloud, 1); hooks_off(); snprintf(deny_dir, sizeof deny_dir, "%s", f.save);
            save_sync_mount(f.save, "0100abc");
            _exit(atomic_load(&g_on) ? 4 : 0);
        }
        int st; waitpid(c, &st, 0);
        CHECK(WIFEXITED(st) && !WEXITSTATUS(st) && local_intact(&f, 1), "sync turns off; the cloud's save does not replace one that could not be read");
    }

    printf("(9) a fetch abandoned at its time limit\n");
    {   char dl[1400], cloudf[1400]; snprintf(dl, sizeof dl, "%s/download", root); snprintf(cloudf, sizeof cloudf, "%s/unused.dmsync", root);
        atomic_store(&hook_fetch_mode, 1); atomic_store(&hook_fetch_ready, 0); atomic_store(&hook_fetch_release, 0);
        int r = fetch_timed(cloudf, dl, 20);
        for (int i = 0; i < 2000 && !atomic_load(&hook_fetch_ready); i++) usleep(1000);
        char part[4096]; snprintf(part, sizeof part, "%s", hook_fetch_dest);
        CHECK(r == -1 && atomic_load(&hook_fetch_ready) && strcmp(part, dl) && !exists(dl), "-1 at the limit; the download went to a file of its own (%s), nothing at the path", part);
        put(dl, "NEW_DOWNLOAD");
        atomic_store(&hook_fetch_release, 1);
        for (int i = 0; i < 2000 && exists(part); i++) usleep(1000);
        usleep(20000);
        CHECK(same(dl, "NEW_DOWNLOAD") && !exists(part), "when it ends it removes its own file and leaves the later download");
        atomic_store(&hook_fetch_mode, 0);
    }

    printf("(10) a fetch in time\n");
    {   char dl[1400], cloudf[1400]; snprintf(dl, sizeof dl, "%s/download2", root); snprintf(cloudf, sizeof cloudf, "%s/c.dmsync", root);
        put(cloudf, "CLOUD"); put(dl, "STALE");
        int r = fetch_timed(cloudf, dl, 5000);
        CHECK(r == 1 && same(dl, "CLOUD") && !exists(hook_fetch_dest), "1: its file is at the path, nothing else left");
        unlink(cloudf);
        r = fetch_timed(cloudf, dl, 5000);
        CHECK(r == 0 && !exists(dl), "no cloud file: 0, and what an earlier fetch left at the path is gone");
    }

    printf("(11) a send with a folder that cannot be read\n");
    {   fixture f; make_fixture(&f, "send_unreadable", 1);
        struct stat before; stat(f.cfile, &before);
        put(f.prog, "LOCAL_NEWER");
        hooks_off(); snprintf(deny_dir, sizeof deny_dir, "%s", f.dev);
        int ok = send_save(f.save, "0100ABC", f.cfile);
        hooks_off();
        struct stat after; stat(f.cfile, &after);
        CHECK(!ok && before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec && before.st_size == after.st_size && before.st_ino == after.st_ino,
              "nothing is sent: the cloud keeps both halves of its save");
    }

    printf("(12) a send when both changed\n");
    {   fixture f; make_fixture(&f, "send_both", 1);
        write_base(f.save, f.cfile, "00000000000000000000000000000000");   // neither side is the last sync's
        time_t now = time(NULL); set_mtime(f.prog, now - 1000); set_mtime(f.isl, now - 1000);
        struct stat before; stat(f.cfile, &before);
        snprintf(q, sizeof q, "%s-backups", f.save);
        CHECK(!send_save(f.save, "0100ABC", f.cfile) && unchanged(f.cfile, &before) && count_dirs(q, " cloud") == 0, "the cloud's is newer: not sent, the cloud's file untouched, nothing to keep");
        set_mtime(f.prog, now + 1000);
        CHECK(!send_save(f.save, "0100ABC", f.cfile) && unchanged(f.cfile, &before) && count_dirs(q, " cloud") == 0, "this one newer: not sent either, the next start decides");
        ss_meta cm; ss_read(f.cfile, NULL, &cm); write_base(f.save, f.cfile, cm.hash);   // what a start that chose this device's save records: the cloud's is the one it replaces
        CHECK(send_save(f.save, "0100ABC", f.cfile) == 1 && cloud_value(f.cfile, "LOCAL"), "after a start that chose this one, it is sent");
    }

    printf("(13) a cloud backup that cannot be completed\n");
    {   fixture f; make_fixture(&f, "mount_backup_fail", 1);
        char remote[1400]; snprintf(remote, sizeof remote, "%s/remote/save/progress", f.dir);
        setxattr(remote, GUEST_NAME, "Progress", 8, 0, XATTR_NOFOLLOW);
        snprintf(p, sizeof p, "%s/remote/save", f.dir); ss_pack(p, "0100abc", f.cfile, &m);
        write_base(f.save, f.cfile, "00000000000000000000000000000000");
        set_mtime(f.prog, time(NULL) + 1000);   // this one is the newer: the start chooses it, keeping the cloud's first
        snprintf(q, sizeof q, "%s-backups", f.save);
        for (int i = 0; i < KEEP_BACKUPS; i++) { snprintf(p, sizeof p, "%s/2001-01-01 00.00.%02d cloud", q, i); mkdirs(p); }
        struct stat before; stat(f.cfile, &before);
        char base_before[SS_HASH + 1], base_after[SS_HASH + 1]; read_base(f.save, f.cfile, base_before);
        fflush(stdout); pid_t c = fork();
        if (!c) {
            setenv("DM_SAVE_SYNC", f.cloud, 1); unsetenv("DM_SAVE_SYNC_CHOICE");
            hooks_off(); snprintf(deny_setxattr_in, sizeof deny_setxattr_in, "-backups/");
            save_sync_mount(f.save, "0100abc");
            pthread_mutex_lock(&g_mu); int want = g_want, failed = g_failed; pthread_mutex_unlock(&g_mu);
            _exit(!want && failed ? 0 : 7);
        }
        int st; waitpid(c, &st, 0);
        read_base(f.save, f.cfile, base_after);
        snprintf(p, sizeof p, "%s/2001-01-01 00.00.00 cloud", q);
        CHECK(WIFEXITED(st) && !WEXITSTATUS(st) && unchanged(f.cfile, &before) && !strcmp(base_before, base_after), "not sent: the cloud's save and the sync state stay");
        CHECK(count_dirs(q, " cloud") == KEEP_BACKUPS && exists(p), "the part of a backup is removed, and the oldest whole one stays (%d)", count_dirs(q, " cloud"));
    }

    printf("(14) the sync state belongs to one cloud file\n");
    {   fixture f; make_fixture(&f, "send_folder", 1);
        ss_meta mine; ss_scan(f.save, &mine); write_base(f.save, f.cfile, mine.hash);
        struct stat before; stat(f.cfile, &before);
        CHECK(send_save(f.save, "0100ABC", f.cfile) == 1 && unchanged(f.cfile, &before), "in step with folder A: nothing to send");
        char b[1400]; snprintf(b, sizeof b, "%s/cloudB/0100ABC/save.dmsync", f.dir);
        CHECK(send_save(f.save, "0100ABC", b) == 1 && cloud_value(b, "LOCAL"), "folder B chosen: the unchanged save goes there");
        set_mtime(f.prog, time(NULL) + 1000);   // the newer of the two, whatever second each was written in
        CHECK(!send_save(f.save, "0100ABC", f.cfile) && unchanged(f.cfile, &before), "back to A, whose save is not this one: nothing is sent, the next start decides between the two");
        snprintf(p, sizeof p, "%s.sync", f.save); FILE *o = fopen(p, "w"); fprintf(o, "base\t%s\n", mine.hash); fclose(o);
        stat(b, &before);
        CHECK(send_save(f.save, "0100ABC", b) == 1 && unchanged(b, &before), "a state file without a cloud line still counts as in step");
    }

    printf("(15) a pull that could not be put back refuses the mount until it is\n");
    {   fixture f; make_fixture(&f, "stuck", 1);
        ss_meta mine; ss_scan(f.save, &mine); write_base(f.save, f.cfile, mine.hash);   // only the cloud's changed: the mount pulls
        fflush(stdout); pid_t c = fork();
        if (!c) { setenv("DM_SAVE_SYNC", f.cloud, 1); fail_moves(3, 4); int r = save_sync_mount(f.save, "0100abc"); _exit(r == -1 && !atomic_load(&g_on) ? 0 : 5); }
        int st; waitpid(c, &st, 0);
        CHECK(WIFEXITED(st) && !WEXITSTATUS(st) && marked(&f), "the mount answers -1 (the save is not mounted), sync stays off, and %s.pull stays", f.save);
        struct stat before; stat(f.cfile, &before);
        setenv("DM_SAVE_SYNC", f.cloud, 1);
        CHECK(save_sync_after_exit(f.save, "0100abc") == 0 && unchanged(f.cfile, &before), "the Mac launcher's send after the host sends nothing: the cloud keeps its save");
        unsetenv("DM_SAVE_SYNC");
        c = fork();
        if (!c) { unsetenv("DM_SAVE_SYNC"); int r = save_sync_mount(f.save, "0100abc"); _exit(r == 0 && !atomic_load(&g_on) ? 0 : 6); }
        waitpid(c, &st, 0);
        snprintf(q, sizeof q, "%s-backups", f.save);
        CHECK(WIFEXITED(st) && !WEXITSTATUS(st) && local_intact(&f, 1) && !marked(&f) && count_dirs(q, " local") == 0,
              "the next start, sync off, puts this device's save back whole before it mounts: the journal and the pull's backup gone");
        setenv("DM_SAVE_SYNC", f.cloud, 1);
        CHECK(save_sync_after_exit(f.save, "0100abc") == 1, "and syncing resumes: in step as before the pull");
        unsetenv("DM_SAVE_SYNC");
    }

    printf("(16) a send whose upload fails\n");
    {   fixture f; make_fixture(&f, "send_store_fail", 1);
        put(f.cfile, "DAMAGED");   // no save can be read from it: the send keeps the file, then replaces it
        write_base(f.save, f.cfile, "00000000000000000000000000000000");
        snprintf(q, sizeof q, "%s-backups", f.save);
        for (int i = 0; i < KEEP_BACKUPS; i++) { snprintf(p, sizeof p, "%s/2001-01-01 00.00.%02d cloud", q, i); mkdirs(p); }
        char title_dir[1400]; snprintf(title_dir, sizeof title_dir, "%s/0100ABC", f.cloud);
        struct stat before; stat(f.cfile, &before);
        chmod(title_dir, 0555);   // the cloud folder refuses the upload's part file
        int ok1 = send_save(f.save, "0100ABC", f.cfile), ok2 = send_save(f.save, "0100ABC", f.cfile);
        chmod(title_dir, 0755);
        snprintf(p, sizeof p, "%s/2001-01-01 00.00.00 cloud", q);
        CHECK(!ok1 && !ok2 && unchanged(f.cfile, &before), "not sent, twice: the cloud keeps its save");
        CHECK(count_dirs(q, " cloud") == KEEP_BACKUPS && exists(p), "no backup of the unchanged cloud file is kept, and the oldest one stays (%d)", count_dirs(q, " cloud"));
        CHECK(send_save(f.save, "0100ABC", f.cfile) == 1 && cloud_value(f.cfile, "LOCAL") && count_dirs(q, " cloud") == KEEP_BACKUPS && !exists(p),
              "once the folder takes it, it is sent, the damaged file is kept and only then the oldest backup goes");
    }

    printf("(17) a pull stopped between its moves\n");
    for (int at = 1; at <= 4; at++) {
        char name[32]; snprintf(name, sizeof name, "pull_ended%d", at);
        fixture f; make_fixture(&f, name, 1);
        ss_meta mine; ss_scan(f.save, &mine); write_base(f.save, f.cfile, mine.hash);   // only the cloud's changed: a start would pull
        fflush(stdout); pid_t c = fork();
        if (!c) { hooks_off(); hook_on = 1; hook_end_at = at; pull(f.save, f.bundle, &m, kept, sizeof kept); _exit(0); }
        int st; waitpid(c, &st, 0);
        CHECK(WIFEXITED(st) && WEXITSTATUS(st) == 9 && marked(&f), "the app ends at move %d of 4: %s.pull is already there", at, f.save);
        struct stat before; stat(f.cfile, &before);
        setenv("DM_SAVE_SYNC", f.cloud, 1);
        int sent = save_sync_after_exit(f.save, "0100abc");
        unsetenv("DM_SAVE_SYNC");
        CHECK(!sent && unchanged(f.cfile, &before), "the Mac launcher's send after it sends nothing: the cloud keeps its save");
        int on = at % 2;   // the next start with sync on (it then pulls again, whole) or off (it only puts the save back)
        fflush(stdout); c = fork();
        if (!c) { if (on) setenv("DM_SAVE_SYNC", f.cloud, 1); else unsetenv("DM_SAVE_SYNC"); hooks_off(); int r = save_sync_mount(f.save, "0100abc"); _exit(r ? 6 : 0); }
        waitpid(c, &st, 0);
        snprintf(q, sizeof q, "%s-backups", f.save); backup_of_side(f.save, "local", p, sizeof p);
        char kp[1600], kd[1600]; snprintf(kp, sizeof kp, "%s/save/progress", p); snprintf(kd, sizeof kd, "%s/save_device/island", p);
        if (on) CHECK(WIFEXITED(st) && !WEXITSTATUS(st) && !marked(&f) && same(f.prog, "REMOTE") && same(f.isl, "REMOTE_ISLAND") && count_dirs(q, " local") == 1 && same(kp, "LOCAL") && same(kd, "LOCAL_ISLAND"),
                      "the next start, sync on, puts this device's save back, then pulls again: the cloud's in place, this device's whole in one backup");
        else CHECK(WIFEXITED(st) && !WEXITSTATUS(st) && !marked(&f) && local_intact(&f, 1) && count_dirs(q, " local") == 0,
                   "the next start, sync off, puts this device's save back whole: no journal, no backup left of the pull");
    }

    printf("== save sync faults: %d checks, %d failed ==\n", checks, fails);
    if (!fails) rm_tree(root);
    return fails != 0;
}
