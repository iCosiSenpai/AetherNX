// Program restart (hle_restart.c, hle_thread.c, hle_oe.c's ExecuteProgram / TryPopLaunchParameter / GetPreviousProgramIndex) with real thread SVCs on host threads, no game files.
// A requester thread calls ExecuteProgram(0, 100 bytes) while other threads are where a game's threads are: in a kernel wait (WaitSynchronization), sleeping in SleepThread,
// spinning in guest code (a C loop module_of calls a module, ended through the pause signal on its gate stack), created and never started, and blocked in the host's
// notification queue (PopNotificationMessage). The main thread waits in the kernel too and comes back through the restart loop (dm_main_restart_jump), runs the restart, and
// checks: every other thread ended before RELEASE, the hooks ran by stage and order, the thread table is empty, the launch parameter pops once and then reports none, the
// previous program index is 0, and a new program (main thread, a thread that runs and exits) starts on fresh tables. A second restart asks for program 1, which is not packed:
// program 0 starts again without the parameter. A parameter too large is refused
#include "../dm.h"
#include <assert.h>
#include <setjmp.h>
#include <signal.h>
#include <stdatomic.h>
#include <sys/mman.h>
#include <unistd.h>
#include "../hle_thread.c"
#include "../hle_restart.c"
#include "../hle_oe.c"
#if defined(__has_feature)
#if __has_feature(thread_sanitizer)
#define NO_SIGNAL_REDIRECT 1   // TSan delivers signals to its own handler first and later, so the redirect of the interrupted context cannot be exercised there
#endif
#endif

// ---- host facilities hle_thread.c and hle_oe.c call ----
struct dm_flags g_flag;
uint64_t g_t0_ns;
pthread_key_t g_key18;
__thread _Atomic int dm_host_work;
void crash_thread_init(void) {}
void guest_thread_init(void) {}
void guest_thread_set_id(uint64_t id) { (void)id; }
void guest_gate_stack(int own_stack) { (void)own_stack; }
void *guest_sym(const char *name) { (void)name; return NULL; }
#include <mach/mach_time.h>
uint64_t now_ns(void) { static mach_timebase_info_data_t tb; if (!tb.denom) mach_timebase_info(&tb); return mach_absolute_time() * tb.numer / tb.denom; }
uint64_t guest_ns(void) { return now_ns(); }
int dm_detclock_enabled(void) { return 0; }
void dm_audio_suspend(int on) { (void)on; }
void guest_clock_freeze_for(int reason, int on) { (void)reason; (void)on; }
void dm_gfx_suspend(int on) { (void)on; }
// "Guest code": while a thread runs spin() it is in a module, so the pause signal sends it to its gate stack
static module_t g_fake_module; static __thread int t_in_guest;
module_t *module_of(const void *p) { (void)p; return t_in_guest ? &g_fake_module : NULL; }
// Each thread's gate stack, mapped on first use (thread.c's own is the rest of the pthread stack)
uint64_t guest_gate_top_self(void) {
    static __thread uint8_t *top;
    if (!top) { uint8_t *m = mmap(NULL, 1 << 18, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0); assert(m != MAP_FAILED); top = m + (1 << 18); }
    return (uint64_t)(uintptr_t)top;
}
static jmp_buf g_jb;
void dm_main_restart_jump(void) { longjmp(g_jb, 1); }
// A thread's guest entry, as thread.c's assembly would enter it (the C function, then ExitThread)
void dm_thread_enter(uint64_t entry, uint64_t arg, uint64_t sp) {
    (void)sp;
    ((void (*)(uint64_t))entry)(arg);
    uint64_t r[32] = {0}; svc_thread(0x0A, r);
    abort();
}
static void timeout(int sig) { (void)sig; const char m[] = "[RED] t_restart timed out\n"; write(2, m, sizeof m - 1); _exit(99); }

// An SVC as the gate makes it: entry and exit hooks around the handler
static void svc(int num, uint64_t *r) { thr_svc_enter(r, 0); svc_thread(num, r); thr_svc_leave(); }
static uint32_t new_thread(void (*fn)(uint64_t), uint64_t arg, int start) {
    uint64_t r[32] = {0, (uint64_t)fn, arg, 0, 44, 0};
    svc(0x08, r); assert(r[0] == 0);
    uint32_t h = (uint32_t)r[1];
    if (start) { r[0] = h; svc(0x09, r); assert(r[0] == 0); }
    return h;
}
static uint32_t new_event(void) { uint64_t r[32] = {0}; svc(0x45, r); assert(r[0] == 0); return (uint32_t)r[2]; }   // CreateEvent: w1 write end, w2 read end
static void wait_forever(uint32_t h) { uint64_t r[32] = {0, (uint64_t)&h, 1, (uint64_t)-1}; svc(0x18, r); }

static _Atomic int g_ready;
static uint32_t g_ev;
static void waiter(uint64_t a) { (void)a; atomic_fetch_add(&g_ready, 1); wait_forever(g_ev); abort(); }
static void sleeper(uint64_t a) { (void)a; atomic_fetch_add(&g_ready, 1); for (;;) { uint64_t r[32] = {5000000}; svc(0x0B, r); } }
static void spin(uint64_t a) { (void)a; guest_gate_top_self(); t_in_guest = 1; atomic_fetch_add(&g_ready, 1); for (;;) atomic_signal_fence(memory_order_seq_cst); }
static void popper(uint64_t a) { (void)a; atomic_fetch_add(&g_ready, 1); h_oe_PopMsg(); abort(); }
static uint8_t g_param[100];
static void requester(uint64_t a) { h_oe_ExecProgram((int)a, g_param, sizeof g_param); abort(); }

// Hooks: the order they run in, and what RELEASE finds
static char g_log[64]; static int g_nlog, g_live_at_release = -1;
static void note(char c) { g_log[g_nlog++] = c; }
static void t_stop(void) { note('S'); }
static void t_release_late(void) { note('r'); }
static void t_release_early(void) {
    note('R'); int n = 0;
    pthread_mutex_lock(&G); for (thr_t *t = g_all; t; t = t->all) n += !t->exited; pthread_mutex_unlock(&G);
    g_live_at_release = n;
}
static void t_reset_before_threads(void) { note('a'); }
static void t_reset_after_threads(void) { note('b'); pthread_mutex_lock(&G); assert(!g_all && !g_wait); for (int i = 0; i < MAX_H; i++) assert(!g_h[i].type); pthread_mutex_unlock(&G); }
DM_RESTART_HOOK(DM_RESTART_STOP, 1, t_stop);
DM_RESTART_HOOK(DM_RESTART_RELEASE, 7, t_release_late);
DM_RESTART_HOOK(DM_RESTART_RELEASE, 5, t_release_early);
DM_RESTART_HOOK(DM_RESTART_RESET, 1, t_reset_before_threads);
DM_RESTART_HOOK(DM_RESTART_RESET, 30, t_reset_after_threads);

static _Atomic int g_ran;
static void short_lived(uint64_t a) { atomic_store(&g_ran, (int)a); }

int main(void) {
    signal(SIGALRM, timeout); alarm(30);
    unsetenv("DM_OE_SCRIPT"); setenv("DM_PREEMPT", "0", 1);
    for (unsigned i = 0; i < sizeof g_param; i++) g_param[i] = (uint8_t)(i * 7 + 1);
    svc_thread_main_init();
    { size_t n = 1; uint8_t b[8]; assert(!dm_launch_param_pop(&n, b, sizeof b) && n == 0); assert(h_oe_PrevProgram() == -1); }   // first boot: none, launched from HOME
    if (!setjmp(g_jb)) {
        g_ev = new_event();
        new_thread(waiter, 0, 1); new_thread(sleeper, 0, 1); new_thread(popper, 0, 1); new_thread(waiter, 0, 0);   // the last one never starts
        int want = 3;
#ifndef NO_SIGNAL_REDIRECT
        new_thread(spin, 0, 1); want++;
#endif
        while (atomic_load(&g_ready) < want) usleep(1000);
        usleep(20000);   // let them reach their waits
        new_thread(requester, 0, 1);
        wait_forever(g_ev);   // the main thread waits in the kernel until the restart ends it
        abort();
    }
    dm_program_restart_run();   // back in the restart loop
    assert(g_live_at_release == 0);
    assert(g_nlog == 5 && !memcmp(g_log, "SRrab", 5));
    // the launch parameter: once, then none
    uint8_t got[128] = {0}; size_t n = 0;
    assert(h_oe_PopLaunchParam(&n, got, sizeof got) == 1 && n == sizeof g_param && !memcmp(got, g_param, sizeof g_param));
    assert(h_oe_PopLaunchParam(&n, got, sizeof got) == 0 && n == 0);
    assert(h_oe_PrevProgram() == 0 && dm_restart_count() == 1);
    // the new program: a main thread and a thread on fresh tables
    uint32_t hmain = svc_thread_main_init();
    assert(hmain == 0x1001);
    uint32_t h = new_thread(short_lived, 7, 1);
    { uint64_t r[32] = {0, (uint64_t)&h, 1, (uint64_t)-1}; svc(0x18, r); assert(r[0] == 0); }
    assert(atomic_load(&g_ran) == 7);
    // program 1 is not packed: program 0 starts again, without the parameter meant for program 1
    if (!setjmp(g_jb)) {
        g_ev = new_event();
        new_thread(requester, 1, 1);
        wait_forever(g_ev);
        abort();
    }
    dm_program_restart_run();
    assert(g_live_at_release == 0);
    assert(g_nlog == 10 && !memcmp(g_log, "SRrabSRrab", 10));
    assert(h_oe_PopLaunchParam(&n, got, sizeof got) == 0 && n == 0);
    assert(h_oe_PrevProgram() == 0 && dm_restart_count() == 2);
    assert(svc_thread_main_init() == 0x1001);
    // a refused request returns and leaves everything as it is
    dm_program_execute(0, g_param, LAUNCH_PARAM_MAX + 1);
    assert(!g_req.pending && dm_restart_count() == 2);
    assert(h_oe_PopLaunchParam(&n, got, sizeof got) == 0);
    puts("restart: threads ended in a kernel wait, a sleep, a native wait, before starting"
#ifndef NO_SIGNAL_REDIRECT
         " and in guest code (signal redirect)"
#endif
         "; hooks by stage and order; launch parameter popped once; a new program on fresh tables; program 1 restarts program 0 without the parameter; large parameters refused");
    return 0;
}
