// Assassin's Creed II (The Ezio Collection, iPhone) reads occlusion reports before completion: replay without GPU work, then publish an empty query's real result.
#include "game_profile.h"
#undef DM_GAME_RENDER_COND
#define DM_GAME_RENDER_COND 1   // Exercise the conditional-rendering path even with a profile that leaves it off.
#define nvn_game_fps nvn_game_fps_mtl_default
#include "../nvn/nvn_mtl.m"
#undef nvn_game_fps
#define g_ft g_ft_hle
#include "../nvn/hle_nvn.c"
#undef g_ft
void *front_metal_layer(void) { return NULL; }
module_t *module_of(const void *p) { (void)p; return NULL; }
module_t *g_mod; int g_nmod;
void svc_thread_dump(void) {}
uint64_t now_ns(void) { return bp_now(); }
static int checks, fails;
#define CHECK(c, label) do { checks++; if (!(c)) { fails++; fprintf(stderr, "FAIL: %s\n", label); } } while (0)

static void report(uint64_t *rec) {
    struct { op_hdr reset; uint64_t type; op_hdr report; uint64_t rtype, addr; op_hdr end; } cmd = {
        {OP_RESET_COUNTER, 16}, NVN_COUNTER_TYPE_SAMPLES_PASSED,
        {OP_REPORT_COUNTER, 24}, NVN_COUNTER_TYPE_SAMPLES_PASSED, (uint64_t)rec, {OP_END, 8}};
    mtl_exec((const uint8_t *)&cmd);
}

int main(void) { @autoreleasepool {
    const char *e = getenv("DM_NVN_OCC_EARLY"); int early = e && !strcmp(e, "1"), trace = occ_trace();
    static uint64_t rec[2][2]; uint64_t before = gpu_ticks(), v = 0;
    state_reset(); atomic_store(&g_cur_frame, 42); report(rec[0]);
    CHECK(g_npost == 1 && g_post[0].kind == 3 && g_post[0].frame == 42, "samples-passed completion retains its encode frame");
    CHECK(early ? rec[0][0] != 0 && rec[0][1] >= before && rec[0][1] <= gpu_ticks() : rec[0][0] == 0 && rec[0][1] == 0, "report is provisional only with DM_NVN_OCC_EARLY=1");
    CHECK(rc_occ_has((uint64_t)rec[0]) && !rc_value((uint64_t)rec[0], &v), "samples-passed stays unknown to conditional rendering");

    // The switch is read once; later resets and submissions must not restart the provisional counter (AC II compares two reports).
    setenv("DM_NVN_OCC_EARLY", early ? "0" : "1", 1);
    g_rc_npend = 0; atomic_store(&g_cur_frame, 44); report(rec[1]);
    CHECK(early ? rec[1][0] > rec[0][0] && rec[1][0] - rec[0][0] == 1ull << 20 : rec[1][0] == 0 && rec[1][1] == 0, "switch is cached and successive provisional reports differ by 1 << 20");
    CHECK(!rc_value((uint64_t)rec[0], &v) && !rc_value((uint64_t)rec[1], &v), "both addresses stay unknown across submissions");
    p_render_cond cond = {.mode = 0, .addr = (uint64_t)rec[0]};
    struct { op_hdr h; p_render_cond cond; op_hdr end; } cmd = {{OP_RENDER_COND, 8 + sizeof cond}, cond, {OP_END, 8}};
    mtl_exec((const uint8_t *)&cmd);
    CHECK(!g_rc_skip, "a condition comparing two samples-passed reports keeps drawing");

    post_rec r = {.n = g_npost, .ops = malloc(g_npost * sizeof *g_post)};
    memcpy(r.ops, g_post, g_npost * sizeof *g_post); g_npost = 0;
    atomic_store(&g_cur_frame, 47); before = gpu_ticks();
    pthread_mutex_lock(&g_post_mu); post_run(&r, 0, 0);
    CHECK(rec[0][0] == 0 && rec[1][0] == 0, "completion overwrites both records with the real zero samples");
    CHECK(rec[0][1] >= before && rec[1][1] >= before && rec[1][1] <= gpu_ticks(), "completion writes timestamps from gpu_ticks");
    CHECK(atomic_load(&g_occ_reports) == (trace ? 2 : 0) && atomic_load(&g_occ_zero) == (trace ? 2 : 0), "trace counts completed and zero-sample reports only when enabled");
    CHECK(atomic_load(&g_occ_lag_sum) == (trace ? 8 : 0) && atomic_load(&g_occ_lag_max) == (trace ? 5 : 0), "trace measures each report's encode-to-completion frame lag");
    occ_report(299); occ_report(300); occ_report(300); occ_report(599); occ_report(600);
    free(g_post); g_post = NULL; g_postcap = 0;
    printf("early occlusion reports (%s): %d checks, %d failed\n", early ? "on" : "off", checks, fails);
    return fails != 0;
} }
