// Per-stage program binding (bind_stages) when the game frees a program that still holds stages. Assassin's Creed II (The Ezio Collection) binds a program to every
// graphics stage, then others to vertex and fragment only, and frees the first one; the next combined program read the freed object's memory, by then other data, and
// crashed in keys_hash. A stage whose object is plainly no longer a program now counts as unbound. No GPU work: the programs' shaders are put in the serial table directly.
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

static NvProg *two_stage(uint64_t serial, prog_t *pg) {
    pg->magic = MAGIC('P', 'R', 'O', 'G'); pg->nstage = 2; pg->serial = serial;
    NvProg *o = [NvProg new];
    NvShader *vs = [NvShader new]; vs->stage = 0; o->sh[0] = vs;
    NvShader *fs = [NvShader new]; fs->stage = 1; o->sh[1] = fs;
    serial_put(serial, o);
    return o;
}

int main(void) { @autoreleasepool {
    static prog_t all, vf, other;   // guest NVNprogram objects
    NvProg *pall = two_stage(940001, &all), *pvf = two_stage(940002, &vf), *pother = two_stage(940003, &other);
    state_reset();

    // A program bound to every graphics stage (vertex, fragment, geometry, both tessellation stages), then another to vertex and fragment: the first keeps the other three
    CHECK(bind_stages(&all, 0x1f) == &all, "one program on every stage is the effective program");
    const prog_t *c = bind_stages(&vf, 0x3);
    CHECK(c != &vf && c != &all && S.bst[2] == &all, "the stages the second bind leaves keep the first program: a combined program");
    NvProg *co = c ? serial_get(c->serial) : nil;
    CHECK(co && co->sh[0] == pvf->sh[0] && co->sh[1] == pvf->sh[1], "the combined program takes vertex and fragment from the second program");

    // The game frees the first program; its memory then holds other data (the crash's object: 0x77c, 0x8f400000116, ...)
    static const uint64_t junk[] = {0x8f40000077cull, 0x8f400000116ull, 0x30001ull, 0x7000000000ull, 0x703df17060ull, 0x23ull};
    for (size_t i = 0; i < sizeof all; i += sizeof junk) memcpy((uint8_t *)&all + i, junk, sizeof all - i < sizeof junk ? sizeof all - i : sizeof junk);
    c = bind_stages(&other, 0x3);   // crashed in keys_hash before: the new combination re-read the freed program's stages
    CHECK(c == &other, "the stages left on the freed program are unbound: the new program alone is effective");
    CHECK(!S.bst[2] && !S.bst[3] && !S.bst[4], "geometry and tessellation are unbound");
    CHECK(g_red_once[162] == 3, "reported (once in the log; counted per stage)");
    NvProg *eff = c ? prog_get(c) : nil;
    CHECK(eff == pother, "the effective program's shaders are its own");

    // Freed memory that starts with a zero word but holds other data: a magic of 0 counts, the stage count gives it away
    state_reset();
    bind_stages(&vf, 0x1f); bind_stages(&other, 0x1);   // vertex from one program, fragment and the rest from the other
    memset(&vf, 0, sizeof vf); vf.nstage = 0x116;       // other data from the second word on
    c = bind_stages(&other, 0x1);
    NvProg *vo = c ? serial_get(c->serial) : nil;   // vertex only: a combined program of that one stage, as Metroid Dread's depth prepass binds
    CHECK(!S.bst[1] && !S.bst[2] && vo && vo->sh[0] == pother->sh[0] && !vo->sh[1], "an object with more than six stages is not a program: its stages are unbound");
    // A finalized program (Finalize clears the magic) keeps its stages, as before: its stages' code is still readable guest memory
    state_reset();
    two_stage(940006, &vf); bind_stages(&vf, 0x1f); bind_stages(&other, 0x1); vf.magic = 0; // NOLINT(clang-analyzer-osx.cocoa.RetainCount): two_stage's NvProg is owned by g_by_serial (serial_put's CFBridgingRetain)
    c = bind_stages(&other, 0x1);
    CHECK(S.bst[1] == &vf && c != &other, "a finalized program (magic 0) keeps its stages");
    // A program given new shaders keeps its stages (a new serial, still a program)
    state_reset();
    bind_stages(&all, 0x1f);   // the junk above: unbound at once
    CHECK(!S.bst[0], "a bind of an object that is not a program binds nothing");
    two_stage(940004, &all); bind_stages(&all, 0x1f); // NOLINT(clang-analyzer-osx.cocoa.RetainCount): two_stage's NvProg is owned by g_by_serial (serial_put's CFBridgingRetain)
    all.serial = 940005; serial_put(940005, pall);
    CHECK(bind_stages(NULL, 0) == &all, "new shaders on a bound program keep its stages");

    // prog_key never reads past the six stages of a program object
    static prog_t big = {.magic = MAGIC('P', 'R', 'O', 'G'), .nstage = 40};
    uint8_t key[8]; CHECK(prog_key(&big, 7, key) == 0, "prog_key refuses a stage past the sixth");

    printf("stale stage bindings: %d checks, %d failed\n", checks, fails);
    return fails != 0;
} }
