// Cloud saves on a volume that is really full: dm/host/save_sync.c through hle_fs.c's own save mount and Commit, as t_save_sync.c drives them, with the device's save
// or the cloud folder on a small disk image this test fills to its last byte (make -C dm/host/tests GAME=<id> full-disk makes the image, mounts it and removes it).
// t_save_sync_faults.c injects ENOSPC into single calls; here the volume refuses every write that needs room, as a full phone or a full iCloud Drive folder does.
// The expected values are written by hand from docs/settings.md (Cloud saves): a send never leaves a part of a save in the cloud, a save brought in replaces the
// device's whole or not at all, and with room again the next start does what this one could not.
//   (1) the cloud folder's volume is full: the game's save is committed on the device; the send fails and says so; the cloud keeps the save it had, whole, with nothing
//       left beside it; the Mac launcher's send after the game fails the same way; with room again the next start sends it
//   (2) the device's volume is full, the cloud has a newer save: the start brings nothing in and leaves the device's save as it was, with no <save>.pull (journal);
//       the cloud's newer save is not replaced by the older one; a save the game writes then is whole, the old one or the new one; with room again the next start
//       brings the cloud's save in and keeps the device's in its backups
// usage: t_save_sync_fulldisk <a folder on the small volume> <a folder on another volume>; it refuses a first volume of 1 GB or more, or the second one's volume
#include "../hle_fs.c"
#include <ctype.h>
#include <sys/statvfs.h>   // not sys/mount.h: its mount() and mount_t are hle_fs.c's own names
#include <sys/time.h>
#include <sys/wait.h>

struct dm_flags g_flag; uint64_t g_t0_ns;
uint64_t now_ns(void) { return clock_gettime_nsec_np(CLOCK_MONOTONIC); }
void dm_guest_write_prepare(void *a, size_t n) { (void)a; (void)n; }

static int fails, checks;
#define CHECK(c, ...) do { checks++; if (!(c)) { fails++; printf("  ✗ "); } else printf("  ✓ "); printf(__VA_ARGS__); printf("\n"); fflush(stdout); } while (0)
static void put(const char *p, const char *s) { FILE *f = fopen(p, "w"); if (!f) return; fputs(s, f); fclose(f); }
static int same(const char *p, const char *s) {
    char b[64] = {0}; FILE *f = fopen(p, "r"); if (!f) return 0; size_t k = fread(b, 1, sizeof b - 1, f); fclose(f);
    return k == strlen(s) && !memcmp(b, s, k);
}
static void mkd(const char *p) { char c[1200]; snprintf(c, sizeof c, "%s", p); for (char *s = c + 1; *s; s++) if (*s == '/') { *s = 0; mkdir(c, 0755); *s = '/'; } mkdir(c, 0755); }
static void set_mtime(const char *p, time_t t) { struct timeval tv[2] = {{t, 0}, {t, 0}}; utimes(p, tv); }
static int exists(const char *p) { return !access(p, F_OK); }
static int entries(const char *dir) {   // names in a folder, Finder's own left out
    int k = 0; DIR *d = opendir(dir); struct dirent *e;
    while (d && (e = readdir(d))) k += strcmp(e->d_name, ".") && strcmp(e->d_name, "..") && strcmp(e->d_name, ".DS_Store");
    if (d) closedir(d);
    return k;
}
static void backup_of(const char *save, const char *side, char *out, size_t n) {
    char dir[1200]; snprintf(dir, sizeof dir, "%s-backups", save); out[0] = 0;
    DIR *d = opendir(dir); struct dirent *e; char best[256] = "";
    size_t sl = strlen(side);
    while (d && (e = readdir(d))) { size_t l = strlen(e->d_name); if (l > sl && e->d_name[l - sl - 1] == ' ' && !strcmp(e->d_name + l - sl, side) && strcmp(e->d_name, best) > 0) strlcpy(best, e->d_name, sizeof best); }
    if (d) closedir(d);
    if (*best) snprintf(out, n, "%s/%s", dir, best);
}
// What the cloud holds of the game file, unpacked into a folder on the volume with room
static int cloud_has(const char *cloud_file, const char *root, const char *file, const char *value) {
    static int k; char into[1200], p[1400]; ss_meta m;
    snprintf(into, sizeof into, "%s/peek%d", root, k++); mkd(into);
    if (ss_read(cloud_file, into, &m)) return 0;
    snprintf(p, sizeof p, "%s/save/%s", into, file); return same(p, value);
}
static Result write_save(const char *path, const char *s) {           // create -> open -> set size -> write -> close, as a game does
    uint64_t h; h_fs_CreateFile(path, 0); Result r = h_fs_OpenFile(&h, path, MODE_WRITE); if (r) return r;
    Result sized = h_fs_SetFileSize(h, (int64_t)strlen(s));
    r = h_fs_WriteFile(h, 0, s, strlen(s), NULL); h_fs_CloseFile(h); return sized ? sized : r;
}

enum { NOT_SENT = 64 };
// One start of the game on a device, in a child process (the host's sync state is once per process): the save mount, then, with a file, the game writing it and
// committing, then a flush. Returns the child's failed steps, plus NOT_SENT when the flush did not leave the save in step with the cloud
static int session(const char *save, const char *cloud, const char *file, const char *value) {
    fflush(stdout); fflush(stderr);
    pid_t p = fork();
    if (!p) {
        setenv("DM_SAVE", save, 1);
        if (cloud) setenv("DM_SAVE_SYNC", cloud, 1); else unsetenv("DM_SAVE_SYNC");
        unsetenv("DM_SAVE_SYNC_CHOICE");
        int bad = h_fs_MountSave("save", NULL) != RES_OK;
        if (file) { char gp[256]; snprintf(gp, sizeof gp, "save:/%s", file); bad += write_save(gp, value) != RES_OK; bad += h_fs_Commit("save") != RES_OK; }
        if (cloud && save_sync_flush(10000) != 1) bad += NOT_SENT;
        fflush(stdout); fflush(stderr); _exit(bad);
    }
    int st; waitpid(p, &st, 0);
    return WIFEXITED(st) ? WEXITSTATUS(st) : 99;
}
// The Mac launcher's send once the host has exited (dm/mac/launcher.c): 1 = in step with the cloud
static int after_exit(const char *save, const char *cloud, const char *title) {
    fflush(stdout); fflush(stderr);
    pid_t p = fork();
    if (!p) { setenv("DM_SAVE", save, 1); setenv("DM_SAVE_SYNC", cloud, 1); int r = save_sync_after_exit(save, title); fflush(stderr); _exit(r); }
    int st; waitpid(p, &st, 0);
    return WIFEXITED(st) ? WEXITSTATUS(st) : 99;
}

static long long free_bytes(const char *p) { struct statvfs s; return statvfs(p, &s) ? -1 : (long long)s.f_bavail * (long long)s.f_frsize; }
// The filler: files that take every byte the volume gives, each in smaller and smaller pieces, until three new files in a row get none (g_full). One file is not
// enough on APFS: when it can grow no more, a new small file still gets a block, and the room of a file removed a moment ago comes back a little later. What statvfs
// calls available is no measure either: APFS reports a reserve there that it gives to no file
static char g_fill[1400]; static int g_full;
static long long fill(const char *volume) {
    snprintf(g_fill, sizeof g_fill, "%s/fill", volume); mkdir(g_fill, 0755);
    static char block[1 << 20]; memset(block, 0xA5, sizeof block);
    long long total = 0; int refused = 0;
    for (int k = 0; k < 100000 && refused < 3; k++) {
        char p[1500]; snprintf(p, sizeof p, "%s/%06d", g_fill, k);
        int fd = open(p, O_WRONLY | O_CREAT | O_EXCL, 0644); long long got = 0;
        if (fd >= 0) {
            for (size_t n = sizeof block; n; n = n > 4096 ? n / 4 : n > 1 ? n / 2 : 0) {
                for (;;) { ssize_t w = write(fd, block, n); if (w <= 0) break; got += w; }
            }
            if (fsync(fd)) got = 0;
            close(fd);
        }
        total += got;
        if (got) refused = 0; else { refused++; usleep(100000); }
    }
    g_full = refused >= 3;
    return total;
}
static void unfill(void) {
    DIR *d = opendir(g_fill); struct dirent *e; char p[1700];
    while (d && (e = readdir(d))) { if (e->d_name[0] == '.') continue; snprintf(p, sizeof p, "%s/%s", g_fill, e->d_name); unlink(p); }
    if (d) closedir(d);
    rmdir(g_fill); sync();
}

int main(int argc, char **argv) {
    if (argc != 3) { fprintf(stderr, "usage: %s <a folder on the small volume> <a folder on another volume>\n", argv[0]); return 2; }
    const char *small = argv[1], *roomy = argv[2];
    struct statvfs fs; struct stat ds, dr;
    if (statvfs(small, &fs) || stat(small, &ds) || stat(roomy, &dr)) { perror(small); return 2; }
    long long size = (long long)fs.f_blocks * (long long)fs.f_frsize;
    // This test fills its first volume: only ever a small one made for it
    if (size >= 1LL << 30 || ds.st_dev == dr.st_dev) {
        fprintf(stderr, "%s is not a small volume of its own (%lld MB): this test fills it, so it is not run there\n", small, size >> 20); return 2;
    }
    char id[24], p[1400], q[1400], back[1400];
    for (size_t i = 0; i <= strlen(DM_GAME_ID); i++) id[i] = (char)toupper((unsigned char)DM_GAME_ID[i]);
    printf("small volume: %s (%lld KB), free %lld KB\n", small, size >> 10, free_bytes(small) >> 10);

    printf("(1) the cloud folder's volume is full\n");
    char A[1200], cloud[1200], cf[1400], cdir[1400];
    snprintf(A, sizeof A, "%s/mac/save", roomy); snprintf(cloud, sizeof cloud, "%s/iCloud Drive/HorizonNative Saves", small);
    snprintf(cdir, sizeof cdir, "%s/%s", cloud, id); snprintf(cf, sizeof cf, "%s/save.dmsync", cdir);
    mkd(A); mkd(cloud);
    snprintf(p, sizeof p, "%s/game.dat", A); put(p, "v1");
    CHECK(session(A, cloud, NULL, NULL) == 0 && cloud_has(cf, roomy, "game.dat", "v1"), "with room, the Mac's session sends its save");
    long long took = fill(small);
    CHECK(took > 0 && g_full, "the volume is full: it takes no more data (%lld KB written; it reports %lld KB available)", took >> 10, free_bytes(small) >> 10);
    int r = session(A, cloud, "game.dat", "v2");
    CHECK(same(p, "v2"), "the game's save is committed on the device");
    CHECK(r == NOT_SENT, "the send fails and the session says it is not in step (%d)", r);
    CHECK(cloud_has(cf, roomy, "game.dat", "v1"), "the cloud keeps the save it had, whole and readable");
    CHECK(entries(cdir) == 1, "nothing is left beside it (%d names in the game's cloud folder)", entries(cdir));
    CHECK(after_exit(A, cloud, id) == 0 && cloud_has(cf, roomy, "game.dat", "v1") && entries(cdir) == 1, "the launcher's send after the game fails the same way");
    snprintf(q, sizeof q, "%s.pull", A); CHECK(!exists(q), "no pull was under way: no %s.pull", "save");
    unfill();
    CHECK(session(A, cloud, NULL, NULL) == 0 && cloud_has(cf, roomy, "game.dat", "v2"), "with room again, the next start sends it");

    printf("(2) the device's volume is full\n");
    char B[1200], A2[1200], cloud2[1200], cf2[1400];
    snprintf(B, sizeof B, "%s/iphone/save", small); snprintf(A2, sizeof A2, "%s/mac2/save", roomy); snprintf(cloud2, sizeof cloud2, "%s/cloud2", roomy);
    snprintf(cf2, sizeof cf2, "%s/%s/save.dmsync", cloud2, id);
    mkd(B); mkd(A2); mkd(cloud2);
    snprintf(p, sizeof p, "%s/game.dat", B); put(p, "b1"); set_mtime(p, time(NULL) - 1000);   // the device's own save, never synced, the older of the two
    snprintf(q, sizeof q, "%s/game.dat", A2); put(q, "a2");
    snprintf(q, sizeof q, "%s/world.bin", A2);   // a save of some size: 300 KB the full volume has no room for
    { FILE *f = fopen(q, "w"); for (int i = 0; f && i < 300 * 1024; i++) fputc('a' + i % 23, f); if (f) fclose(f); }
    CHECK(session(A2, cloud2, NULL, NULL) == 0 && cloud_has(cf2, roomy, "game.dat", "a2"), "the Mac sends a newer, larger save");
    took = fill(small);
    CHECK(took > 0 && g_full, "the volume is full: it takes no more data (%lld KB written; it reports %lld KB available)", took >> 10, free_bytes(small) >> 10);
    r = session(B, cloud2, NULL, NULL);
    snprintf(q, sizeof q, "%s/world.bin", B);
    CHECK(same(p, "b1") && !exists(q), "the start brings nothing in: the device's save is as it was, no part of the cloud's in it (session %d)", r);
    snprintf(q, sizeof q, "%s.pull", B); CHECK(!exists(q), "no move was begun: no save.pull left pending");
    CHECK(cloud_has(cf2, roomy, "game.dat", "a2"), "the cloud's newer save is not replaced by the device's older one");
    r = session(B, NULL, "game.dat", "b2");
    CHECK(same(p, "b1") || same(p, "b2"), "a save the game writes on the full volume is whole: the old one or the new one (%s, session %d)", same(p, "b2") ? "new" : "old", r);
    int had_b2 = same(p, "b2");
    unfill();
    r = session(B, cloud2, NULL, NULL);
    snprintf(q, sizeof q, "%s/world.bin", B);
    if (had_b2) {   // the device saved later than the cloud's save was made: the newer one wins, and it is the device's
        CHECK(r == 0 && same(p, "b2") && cloud_has(cf2, roomy, "game.dat", "b2"), "with room again, the device's newer save goes out (session %d)", r);
        backup_of(B, "cloud", back, sizeof back); CHECK(*back, "and the cloud's is kept in the device's backups (%s)", back);
    } else {
        CHECK(r == 0 && same(p, "a2") && exists(q), "with room again, the next start brings the cloud's save in (session %d)", r);
        backup_of(B, "local", back, sizeof back); snprintf(q, sizeof q, "%s/save/game.dat", back);
        CHECK(*back && same(q, "b1"), "and the device's own is kept in its backups (%s)", back);
    }

    printf("t_save_sync_fulldisk: %d checks, %d failed\n", checks, fails);
    return fails != 0;
}
