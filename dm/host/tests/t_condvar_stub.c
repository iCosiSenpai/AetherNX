// Stubs for t_condvar: host facilities of hle_thread.c that the unit test does not use
#include "../dm.h"
struct dm_flags g_flag;
uint64_t g_t0_ns;
void crash_thread_init(void) {}
void guest_thread_init(void) {}
void guest_thread_set_id(uint64_t id) { (void)id; }
void guest_gate_stack(int own_stack) { (void)own_stack; }
// The notification scheduler test supplies a C entry for real thread SVCs.
#ifndef DM_TEST_THREAD_ENTER
void dm_thread_enter(uint64_t entry, uint64_t arg, uint64_t sp) { (void)entry; (void)arg; (void)sp; abort(); }
#endif
void *guest_sym(const char *name) { (void)name; return NULL; }
module_t *module_of(const void *p) { (void)p; return NULL; }
#include <mach/mach_time.h>
uint64_t now_ns(void) { static mach_timebase_info_data_t tb; if (!tb.denom) mach_timebase_info(&tb); return mach_absolute_time() * tb.numer / tb.denom; }
uint64_t guest_ns(void) { return now_ns(); }
int dm_detclock_enabled(void) { return 0; }
__thread _Atomic int dm_host_work;   // referenced by hle_thread.c; in the host it is defined in hle_nvn.c
pthread_key_t g_key18;   // read by hle_thread.c's SVC entry and pause signal; in the host it is defined in loader.c (never created here: those paths do not run)
// The program restart's calls into main.c, thread.c and hle_restart.c (weak: t_restart supplies its own): no gate stack, no restart loop, no launch parameter
__attribute__((weak)) uint64_t guest_gate_top_self(void) { return 0; }
__attribute__((weak)) void dm_main_restart_jump(void) { abort(); }
__attribute__((weak)) int dm_launch_param_pop(size_t *out, void *buf, size_t n) { (void)buf; (void)n; if (out) *out = 0; return 0; }
__attribute__((weak)) int dm_program_previous_index(void) { return -1; }
__attribute__((weak)) void dm_program_execute(int index, const void *param, size_t n) { (void)index; (void)param; (void)n; }
