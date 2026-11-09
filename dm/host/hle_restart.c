// Program restart inside this process: nn::oe::ExecuteProgram. On Horizon the call ends the application's process and the system starts the requested program of the same
// application, which reads the caller's parameter with nn::oe::TryPopLaunchParameter. Assassin's Creed The Ezio Collection runs its game menu in program 0 and starts a game by
// calling ExecuteProgram(0, <100 bytes>) and waiting to be ended. An iOS app cannot start itself again, and the Mac and iOS share this host, so the restart happens in place:
//   1. dm_program_execute (on the calling guest thread): copy the parameter, mark every guest thread for ending (hle_thread.c dm_threads_kill_all), run the STOP hooks, end the caller.
//   2. A marked thread ends at its next SVC entry or exit, inside a kernel wait, or, while it runs guest code, through the pause signal, which sends it to its gate stack to exit.
//      The main guest thread does not exit: it jumps back to main.c's restart loop (dm_main_restart_jump), which calls dm_program_restart_run.
//   3. dm_program_restart_run (on the main guest thread, outside guest code): wait for every other thread to end, run the RELEASE hooks (guest memory still holds the old program),
//      then the RESET hooks (guest memory remapped, the modules' data restored and relocated, the per-program tables cleared), then publish the launch parameter. main.c enters
//      the program again from its start: nnosInitialize, the SDK's startup, the modules' constructors, nnMain.
// hle_oe.c's ExecuteProgram restarts in place a program that starts itself again, and this program, without the parameter, when the requested one cannot start here: the game
// comes back to its start. Returning to the game instead, as before, left it waiting to be ended, its picture frozen and its music going on (the Ezio Collection's Brotherhood is
// program 1).
#include "hle.h"
#include <mach-o/getsect.h>
#include <mach-o/ldsyms.h>
#include <stdatomic.h>

#define LAUNCH_PARAM_MAX (64u << 10)   // a parameter larger than this is refused (Assassin's Creed The Ezio Collection passes 100 bytes)
static pthread_mutex_t g_mu = PTHREAD_MUTEX_INITIALIZER;
static struct { int pending, index; uint8_t *param; size_t n; } g_req;                 // the restart under way (g_mu)
static struct { int set; uint8_t *param; size_t n; } g_lp;                             // the launch parameter the running program has not popped yet (g_mu)
static int g_prev_index = -1;                                                          // the program that started this one, -1 = started from HOME (g_mu)
static _Atomic unsigned g_restarts;

unsigned dm_restart_count(void) { return atomic_load(&g_restarts); }
int dm_program_previous_index(void) { pthread_mutex_lock(&g_mu); int v = g_prev_index; pthread_mutex_unlock(&g_mu); return v; }

// nn::oe::TryPopLaunchParameter: the parameter the program that started this one passed, once; 0 when there is none (any more). The whole parameter's size goes to *out, and as
// much of it as fits into buf
int dm_launch_param_pop(size_t *out, void *buf, size_t n) {
    pthread_mutex_lock(&g_mu);
    int ok = g_lp.set;
    if (ok) {
        if (buf && n) memcpy(buf, g_lp.param, g_lp.n < n ? g_lp.n : n);
        if (out) *out = g_lp.n;
        free(g_lp.param); g_lp.param = NULL; g_lp.n = 0; g_lp.set = 0;
    } else if (out) *out = 0;
    pthread_mutex_unlock(&g_mu);
    if (ok) LOG("oe::TryPopLaunchParameter: the launch parameter was taken (%zu bytes)", out ? *out : (size_t)0);
    return ok;
}

static int hook_cmp(const void *a, const void *b) {
    const dm_restart_hook *x = *(const dm_restart_hook *const *)a, *y = *(const dm_restart_hook *const *)b;
    return x->order != y->order ? (x->order > y->order) - (x->order < y->order) : strcmp(x->name, y->name);
}
void dm_restart_run_stage(int stage) {
    unsigned long sz = 0;
    const dm_restart_hook *h = (const dm_restart_hook *)(const void *)getsectiondata(&_mh_execute_header, "__DATA", "swrestart", &sz);
    unsigned n = h ? (unsigned)(sz / sizeof *h) : 0, k = 0;
    const dm_restart_hook **v = calloc(n ? n : 1, sizeof *v);
    if (!v) die("restart: hook list allocation failed");
    for (unsigned i = 0; i < n; i++) if (h[i].stage == stage) v[k++] = &h[i];
    qsort(v, k, sizeof *v, hook_cmp);
    for (unsigned i = 0; i < k; i++) {
        uint64_t t0 = now_ns(); v[i]->fn(); uint64_t dt = now_ns() - t0;
        if (dt > 50000000ull) LOG("restart: %s took %.0f ms", v[i]->name, dt / 1e6);
    }
    free(v);
}

void dm_threads_kill_all(void);                 // hle_thread.c
int dm_threads_kill_wait(uint64_t timeout_ns);  // hle_thread.c: guest threads still running when the time is up
__attribute__((noreturn)) void dm_thread_terminate_on_gate_stack(void);   // hle_thread.c

// nn::oe::ExecuteProgram on a guest thread. Returns only when the request is refused (a parameter too large); otherwise the calling thread ends
void dm_program_execute(int index, const void *param, size_t n) {
    if (n > LAUNCH_PARAM_MAX || (n && !param)) {
        LOG("[RED] oe::ExecuteProgram(%d, %zu bytes of parameters): a launch parameter of more than %u bytes is not kept; the game carries on", index, n, LAUNCH_PARAM_MAX);
        return;
    }
    uint8_t *copy = n ? malloc(n) : NULL;
    if (n && !copy) die("restart: launch parameter allocation failed");
    if (n) memcpy(copy, param, n);   // guest memory: copied before any thread ends
    pthread_mutex_lock(&g_mu);
    int again = g_req.pending;
    if (!again) { g_req.pending = 1; g_req.index = index; g_req.param = copy; g_req.n = n; }
    pthread_mutex_unlock(&g_mu);
    if (again) { free(copy); dm_thread_terminate_on_gate_stack(); }   // a second thread asked while a restart is under way: it ends like the others
    LOG("oe::ExecuteProgram(%d, %zu bytes of parameters): restarting the program inside this process (restart %u)", index, n, dm_restart_count() + 1);
    dm_threads_kill_all();
    dm_restart_run_stage(DM_RESTART_STOP);
    dm_thread_terminate_on_gate_stack();
}

// On the main guest thread, back in main.c's restart loop: see the file comment
void dm_program_restart_run(void) {
    uint64_t t0 = now_ns();
    int left = dm_threads_kill_wait(10ull * 1000000000ull);
    if (left) LOG("[RED] restart: %d guest thread(s) did not end within 10 s; they end at their next SVC, and the restart goes on", left);
    uint64_t t1 = now_ns();
    dm_restart_run_stage(DM_RESTART_RELEASE);
    dm_restart_run_stage(DM_RESTART_RESET);
    pthread_mutex_lock(&g_mu);
    free(g_lp.param);
    g_lp.set = g_req.n > 0; g_lp.param = g_req.param; g_lp.n = g_req.n; g_prev_index = g_req.index;   // no parameter: TryPopLaunchParameter finds none, as after HOME
    g_req.param = NULL; g_req.n = 0; g_req.pending = 0;
    pthread_mutex_unlock(&g_mu);
    atomic_fetch_add(&g_restarts, 1);
    LOG("restart: the guest threads ended in %.0f ms, the program state was reset in %.0f ms; entering program %d again with a %zu-byte launch parameter",
        (t1 - t0) / 1e6, (now_ns() - t1) / 1e6, g_prev_index, g_lp.n);
}
