// Exercise the real HLE, forced-takeover and stub indexes with synthetic Mach-O sections; no game files required.
#include "../hle.h"
#include <mach-o/getsect.h>
#include <assert.h>
#include <signal.h>
#include <sys/resource.h>
#include <sys/wait.h>
#include <unistd.h>

static hle_ent entries[4];
static hle_force_ent forces[3];
static int have_sections;
static uint8_t *test_section(const struct mach_header_64 *mh, const char *seg, const char *sect, unsigned long *size) {
    (void)mh; assert(!strcmp(seg, "__DATA"));
    *size = 0;
    if (!have_sections) return NULL;
    if (!strcmp(sect, "swhle")) { *size = sizeof entries; return (uint8_t *)entries; }
    assert(!strcmp(sect, "swforce")); *size = sizeof forces; return (uint8_t *)forces;
}
#define getsectiondata test_section
#include "../hle.c"
#include "../loader.c"
void mtl_present_screen(uint32_t w, uint32_t h) { (void)w; (void)h; }   // loader.c: a screen taller than 16:9; no renderer here
#undef getsectiondata

struct dm_flags g_flag;
uint64_t unimpl_stubs[MAX_STUB];
uint64_t now_ns(void) { return 0; }
uint64_t guest_ns(void) { return 0; }
uint64_t guest_ticks(void) { return 0; }
void guest_clock_read_wait(void) {}
void hlecount_seal(void) {}
int svc_nro_deactivate(module_t *m) { m->loaded = 0; return 1; }   // no memory mappings in this fixture
void thr_svc_enter(uint64_t *r, uint64_t a) { (void)r; (void)a; }
void thr_svc_leave(void) {}
void dm_spin_wait(uint64_t r, uint64_t a) { (void)r; (void)a; }
uint64_t svc_dispatch(int n, uint64_t *r, uint64_t a) { (void)n; (void)r; (void)a; return 0; }
static const char *wrap_kind, *wrap_name;
static unsigned wraps;
void *hlecount_wrap(const char *kind, const char *name, void *fn) {
    wrap_kind = kind; wrap_name = name; wraps++; return fn;
}

static void reset_sections(void) {
    free(g_hle_idx); g_hle_idx = NULL; g_hle_mask = 0; g_hle_sec = NULL;
    free(g_fidx); g_fidx = NULL; g_fmask = 0;
    free(g_force_hits); g_force_hits = NULL;
}

// Failures run in a child, so duplicate rejection and the hard stub limit are checked without killing the suite.
static void expect_abort(int duplicate) {
    pid_t pid = fork(); assert(pid >= 0);
    if (!pid) {
        struct rlimit lim = {0, 0}; setrlimit(RLIMIT_CORE, &lim);
        freopen("/dev/null", "w", stderr);
        if (duplicate) { forces[2] = forces[0]; force_init(); }
        else resolve_import(NULL, "one_more_missing_symbol");
        _exit(0);
    }
    int status; assert(waitpid(pid, &status, 0) == pid);
    assert(WIFSIGNALED(status) && WTERMSIG(status) == SIGABRT);
}

// parse_dynamic on synthetic modules (docs/code-review.md, symbol-table sizing): the count comes from DT_HASH or DT_GNU_HASH, not from where the tables lie, and every table
// and name is checked against the module. A 4 KiB image: MOD0 at 0x20, the dynamic table at 0x40, strings at 0x100, the hash table at 0x180, symbols at 0x200
enum { IMG = 4096 };
static uint8_t img[IMG] __attribute__((aligned(16))); static module_t dm_mod;
static void layout(int hash_tag, uint64_t symtab, uint64_t strtab) {
    memset(img, 0, sizeof img); memset(&dm_mod, 0, sizeof dm_mod);
    dm_mod.base = img; dm_mod.size = IMG; strcpy(dm_mod.name, "synthetic");
    *(uint32_t *)(img + 4) = 0x20; memcpy(img + 0x20, "MOD0", 4); *(int32_t *)(img + 0x24) = 0x20;
    Elf64_Dyn *d = (Elf64_Dyn *)(img + 0x40); int n = 0;
    d[n++] = (Elf64_Dyn){.d_tag = DT_SYMTAB, .d_un.d_ptr = symtab};
    d[n++] = (Elf64_Dyn){.d_tag = DT_STRTAB, .d_un.d_ptr = strtab};
    d[n++] = (Elf64_Dyn){.d_tag = 10 /* DT_STRSZ */, .d_un.d_val = 16};
    if (hash_tag) d[n++] = (Elf64_Dyn){.d_tag = hash_tag, .d_un.d_ptr = 0x180};
    memcpy(img + strtab, "\0symbol\0other\0", 14);
    Elf64_Sym *s = (Elf64_Sym *)(img + symtab);
    s[1] = (Elf64_Sym){.st_name = 1, .st_shndx = 1, .st_value = 0x300};
    s[2] = (Elf64_Sym){.st_name = 8, .st_shndx = 1, .st_value = 0x310};
}
static int parse_dies(void) {   // parse_dynamic in a child: 1 when it stopped with its diagnostic (abort)
    fflush(stdout); pid_t pid = fork(); assert(pid >= 0);
    if (!pid) { struct rlimit lim = {0, 0}; setrlimit(RLIMIT_CORE, &lim); freopen("/dev/null", "w", stderr); freopen("/dev/null", "w", stdout); parse_dynamic(&dm_mod); _exit(0); }
    int status; assert(waitpid(pid, &status, 0) == pid);
    return WIFSIGNALED(status) && WTERMSIG(status) == SIGABRT;
}
static void dynamic_tables(void) {
    // DT_HASH (nbucket 1, nchain 3: the null symbol and two), strings before symbols: the layout whose pointer difference once asked for 8 GiB
    layout(4, 0x200, 0x100); uint32_t *h = (uint32_t *)(img + 0x180); h[0] = 1; h[1] = 3;
    parse_dynamic(&dm_mod);
    assert(dm_mod.nsym == 3 && module_sym(&dm_mod, "symbol") == img + 0x300 && module_sym(&dm_mod, "other") == img + 0x310 && !module_sym(&dm_mod, "absent"));
    free(dm_mod.symh);
    // DT_GNU_HASH only: nbuckets 1, symoffset 1, one bloom word; bucket 0 starts at symbol 1, whose chain ends at symbol 2 (bit 0 set)
    layout(0x6ffffef5, 0x200, 0x100); h = (uint32_t *)(img + 0x180); h[0] = 1; h[1] = 1; h[2] = 1; h[3] = 0;
    h[6] = 1; h[7] = 0x10; h[8] = 0x21;   // bloom (8 bytes) at h[4..5], bucket h[6], chain h[7..8]
    parse_dynamic(&dm_mod);
    assert(dm_mod.nsym == 3 && module_sym(&dm_mod, "other") == img + 0x310);
    free(dm_mod.symh);
    // Neither hash: the symbol table running up to the string table after it (0x200 .. 0x248 = 3 symbols)
    layout(0, 0x200, 0x248); parse_dynamic(&dm_mod);
    assert(dm_mod.nsym == 3 && module_sym(&dm_mod, "symbol") == img + 0x300);
    free(dm_mod.symh);
    // Damaged or unknown layouts stop with a diagnostic instead of reading past the module
    layout(0, 0x200, 0x100); assert(parse_dies());                                                      // no hash, strings first: the count is unknown
    layout(4, 0x200, 0x100); h = (uint32_t *)(img + 0x180); h[0] = 1; h[1] = 1u << 20; assert(parse_dies());   // nchain past the module
    layout(4, 0x200, 0x100); h = (uint32_t *)(img + 0x180); h[0] = 1; h[1] = 3;
    ((Elf64_Sym *)(img + 0x200))[2].st_name = 40; assert(parse_dies());                                // a name outside DT_STRSZ
    layout(4, 0x200, 0x100); *(int32_t *)(img + 0x24) = IMG; assert(parse_dies());                     // MOD0 points the dynamic table past the module
    layout(4, 0x200, 0x100); h = (uint32_t *)(img + 0x180); h[0] = 1; h[1] = 3;
    memset(img + 0x40, 0xff, IMG - 0x40); assert(parse_dies());                                         // no DT_NULL before the module ends
    puts("Dynamic tables: DT_HASH, DT_GNU_HASH and adjacent layouts counted; damaged layouts refused: OK");
}
// Relocation tables and the slots they write lie inside the module (relocs_of, reloc_slot, relr_apply): one R_AARCH64_RELATIVE at 0x400 (DT_RELA) or a DT_RELR table at 0x420
static void reloc_layout(uint64_t rela, uint64_t relasz, uint64_t r_offset, uint64_t relr, uint64_t relrsz) {
    layout(4, 0x200, 0x100); uint32_t *h = (uint32_t *)(img + 0x180); h[0] = 1; h[1] = 3;
    Elf64_Dyn *d = (Elf64_Dyn *)(img + 0x40); while (d->d_tag) d++;
    if (relasz) { *d++ = (Elf64_Dyn){.d_tag = DT_RELA, .d_un.d_ptr = rela}; *d++ = (Elf64_Dyn){.d_tag = DT_RELASZ, .d_un.d_val = relasz}; }
    if (relrsz) { *d++ = (Elf64_Dyn){.d_tag = DT_RELR, .d_un.d_ptr = relr}; *d++ = (Elf64_Dyn){.d_tag = DT_RELRSZ, .d_un.d_val = relrsz}; }
    *(Elf64_Rela *)(img + 0x400) = (Elf64_Rela){.r_offset = r_offset, .r_info = R_AARCH64_RELATIVE, .r_addend = 0x10};
}
static int relocate_dies(void) {
    fflush(stdout); pid_t pid = fork(); assert(pid >= 0);
    if (!pid) { struct rlimit lim = {0, 0}; setrlimit(RLIMIT_CORE, &lim); freopen("/dev/null", "w", stderr); freopen("/dev/null", "w", stdout); parse_dynamic(&dm_mod); relocate(&dm_mod); _exit(0); }
    int status; assert(waitpid(pid, &status, 0) == pid);
    return WIFSIGNALED(status) && WTERMSIG(status) == SIGABRT;
}
static void relocation_tables(void) {
    reloc_layout(0x400, sizeof(Elf64_Rela), 0x600, 0, 0); assert(!relocate_dies());
    parse_dynamic(&dm_mod); relocate(&dm_mod); assert(*(uint64_t *)(img + 0x600) == (uint64_t)img + 0x10); free(dm_mod.symh);   // a slot inside: written
    reloc_layout(0x400, sizeof(Elf64_Rela), 0xfffffffffffffff8ull, 0, 0); assert(relocate_dies());                           // 8 bytes before the base
    reloc_layout(0x400, sizeof(Elf64_Rela), IMG - 4, 0, 0); assert(relocate_dies());                                         // a slot running past the end
    reloc_layout(IMG - 8, sizeof(Elf64_Rela), 0x600, 0, 0); assert(relocate_dies());                                         // the table running past the end
    reloc_layout(0x400, (uint64_t)1 << 40, 0x600, 0, 0); assert(relocate_dies());                                            // a size larger than the module
    reloc_layout(0, 0, 0, 0x420, 16); ((uint64_t *)(img + 0x420))[0] = 0x600; ((uint64_t *)(img + 0x420))[1] = 0x3;          // start 0x600, bitmap: the next slot (0x608)
    *(uint64_t *)(img + 0x600) = 1; *(uint64_t *)(img + 0x608) = 2;
    parse_dynamic(&dm_mod); relocate(&dm_mod); assert(*(uint64_t *)(img + 0x600) == (uint64_t)img + 1 && *(uint64_t *)(img + 0x608) == (uint64_t)img + 2); free(dm_mod.symh);
    reloc_layout(0, 0, 0, 0x420, 8); ((uint64_t *)(img + 0x420))[0] = IMG; assert(relocate_dies());                           // a start past the end
    reloc_layout(0, 0, 0, 0x420, 16); ((uint64_t *)(img + 0x420))[0] = IMG - 16; ((uint64_t *)(img + 0x420))[1] = 1ull << 63 | 1;   // a bitmap bit past the end
    assert(relocate_dies());
    reloc_layout(0, 0, 0, IMG - 8, 64); assert(relocate_dies());                                                            // the table running past the end
    puts("Relocation tables: slots and tables inside the module applied; outside ones refused: OK");
}

int main(void) {
    // Empty/missing sections must still give misses after lazy initialization.
    assert(!hle_implements("absent")); assert(!hle_implements("absent"));
    force_init(); assert(!force_lookup("absent")); reset_sections();

    // Three different names in the same initial bucket exercise probing and a duplicate behind a collision.
    char names[3][32]; unsigned found = 0;
    for (unsigned i = 0; found < 3; i++) {
        char candidate[32]; snprintf(candidate, sizeof candidate, "symbol_%u", i);
        if ((name_h(candidate) & 15) == 15) strcpy(names[found++], candidate);
    }
    int values[5];
    entries[0] = (hle_ent){names[0], &values[0]};
    entries[1] = (hle_ent){names[1], &values[1]};
    entries[2] = (hle_ent){names[1], &values[2]};
    entries[3] = (hle_ent){names[2], &values[3]};
    for (unsigned i = 0; i < 3; i++) forces[i] = (hle_force_ent){names[i], &values[i], "test"};
    have_sections = 1; force_init();
    for (unsigned i = 0; i < 3; i++) {
        unsigned before = wraps;
        assert(hle_implements(names[i]) && wraps == before);
        uint64_t want = (uint64_t)&values[i == 2 ? 3 : i];
        assert(resolve_import(NULL, names[i]) == want);
        assert(!strcmp(wrap_kind, "HLE") && !strcmp(wrap_name, names[i]));
        assert(force_lookup(names[i]) == &values[i]);
        assert(!strcmp(wrap_kind, "FORCE") && !strcmp(wrap_name, names[i]));
        assert(g_force_hits[i] == 1);
    }
    assert(!hle_implements("absent") && !force_lookup("absent") && !g_nstub);
    assert(force_lookup(names[0]) == &values[0] && g_force_hits[0] == 2);
    expect_abort(1);

    // Fill through every growth boundary, then query in reverse using different pointers to the same names.
    static char missing[MAX_STUB][32];
    for (unsigned i = 0; i < MAX_STUB; i++) {
        snprintf(missing[i], sizeof missing[i], "missing_%u", i);
        assert(resolve_import(NULL, missing[i]) == (uint64_t)&unimpl_stubs[i]);
        assert(!strcmp(wrap_kind, "STUB") && !strcmp(wrap_name, missing[i]));
    }
    for (unsigned i = MAX_STUB; i-- > 0;) {
        char copy[32]; strcpy(copy, missing[i]);
        assert(resolve_import(NULL, copy) == (uint64_t)&unimpl_stubs[i]);
    }
    assert(g_nstub == MAX_STUB); expect_abort(0);
    reset_sections();
    dynamic_tables(); relocation_tables();
    puts("Symbol indexes: collisions, duplicate precedence/rejection, misses, wrappers and 4096 reusable stubs: OK");
    return 0;
}
