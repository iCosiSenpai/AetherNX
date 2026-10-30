// The platform's fetch for t_save_sync_faults.c, in a file of its own so that it replaces save_sync.c's weak default at link time, as SaveSync.m does on the iPhone.
// Mode 0: a plain copy (the default's behaviour). Mode 1: writes OLD_DOWNLOAD to its destination, says so, and holds until released, as a download iCloud
// finishes after the host stopped waiting for it.
#include "../save_sync.h"
#include <errno.h>
#include <fcntl.h>
#include <stdatomic.h>
#include <stdio.h>
#include <unistd.h>

_Atomic int hook_fetch_mode, hook_fetch_ready, hook_fetch_release, hook_fetch_calls;
char hook_fetch_dest[4096];

int front_save_sync_fetch(const char *cloud, const char *local) {
    atomic_fetch_add(&hook_fetch_calls, 1);
    snprintf(hook_fetch_dest, sizeof hook_fetch_dest, "%s", local);
    if (atomic_load(&hook_fetch_mode) == 1) {
        FILE *f = fopen(local, "w"); if (!f) return -1;
        fputs("OLD_DOWNLOAD", f); fclose(f);
        atomic_store(&hook_fetch_ready, 1);
        while (!atomic_load(&hook_fetch_release)) usleep(1000);
        return 1;
    }
    int in = open(cloud, O_RDONLY); if (in < 0) return errno == ENOENT ? 0 : -1;
    int out = open(local, O_WRONLY | O_CREAT | O_TRUNC, 0644); if (out < 0) { close(in); return -1; }
    char b[65536]; ssize_t k; int r = 1;
    while ((k = read(in, b, sizeof b)) > 0) if (write(out, b, (size_t)k) != k) { r = -1; break; }
    if (k < 0) r = -1;
    close(in); if (close(out)) r = -1;
    return r;
}
