// Assassin's Creed II (The Ezio Collection, iPhone): two of three GPU-written visibility images start 8 bytes past a 16-byte boundary. Exercise the host's image bindings and
// completion copy on R32Uint views at offsets 4, 8 and 12, including another descriptor / stage, a sampled reader, untouched elements and staging-block rollover. With
// DM_NVN_TBUF_WRITEBACK=0 the same stores land at the boundary below on Apple GPUs; report and check that shift rather than treating the old behaviour as a working writeback.
#include "../nvn/nvn_mtl.m"
void *front_metal_layer(void) { return NULL; }
module_t *module_of(const void *p) { (void)p; return NULL; }
module_t *g_mod; int g_nmod;
void svc_thread_dump(void) {}
uint64_t now_ns(void) { return bp_now(); }
static int checks, fails;
#define CHECK(c, label) do { checks++; if (!(c)) { fails++; fprintf(stderr, "FAIL: %s\n", label); } } while (0)
enum { N = 67, POOL = 16384 };
static NvShader *writer, *reader; static id<MTLComputePipelineState> wp, rp;

// The completion half also runs without a GPU (--post): the retained snapshot must outlive its creator, copy only the view and be consumed once, whether feedback or a waiter claims it.
@interface TbufSnapshot : NSObject { @public uint8_t bytes[64]; } @end
@implementation TbufSnapshot
- (void *)contents { return bytes; }
@end
static int completion_cases(void) {
    for (unsigned off = 4; off < 16; off += 4) {
        uint8_t guest[64]; memset(guest, 0xa5, sizeof guest); __weak TbufSnapshot *weak;
        post_rec r = {.fence = off, .n = 1, .ops = calloc(1, sizeof(post_op))};
        @autoreleasepool {
            TbufSnapshot *b = [TbufSnapshot new]; weak = b;
            const uint32_t values[3] = {1, 2, 3}; memcpy(b->bytes + 16, values, sizeof values);
            tbuf_wb *m = malloc(sizeof *m); *m = (tbuf_wb){(void *)CFBridgingRetain(b), guest + off, 16, sizeof values};
            r.ops[0] = (post_op){.kind = 5, .vis = m};
        }
        @autoreleasepool {   // a weak load may autorelease a temporary strong reference: drain that too before testing the completion's release
            CHECK(weak != nil && guest[off] == 0xa5, "pending completion retains its staging snapshot and leaves the guest untouched");
            int claimed = post_claim(&r, off); CHECK(claimed, "completion record can be claimed"); if (claimed) post_run(&r, 0, 0);
        }
        const uint32_t want[3] = {1, 2, 3}; CHECK(!memcmp(guest + off, want, sizeof want), "post_run copies the whole view to its exact guest offset");
        int guards = 1; for (unsigned i = 0; i < sizeof guest; i++) if (i < off || i >= off + sizeof want) guards &= guest[i] == 0xa5;
        CHECK(guards && weak == nil, "completion preserves surrounding bytes and releases its staging snapshot");
        CHECK(!post_claim(&r, off), "a later feedback handler or waiter cannot copy back or release the snapshot twice");
    }
    printf("image buffer completion: %d checks, %d failed\n", checks, fails); return fails != 0;
}
static void run_kernel(NvShader *sh, id<MTLComputePipelineState> ps, int n) {
    id<MTL4ComputeCommandEncoder> e = enc_c_begin(nil); enc_c_pso(e, ps);
    CHECK(encode_args((id<MTLCommandEncoder>)e, sh, 5, 0), "production compute arguments encoded");
    enc_c_dispatch(e, MTLSizeMake(n, 1, 1), MTLSizeMake(1, 1, 1)); enc_c_end(e);
}
static void image_case(unsigned off) {
    uint8_t *mem; if (posix_memalign((void **)&mem, POOL, POOL)) abort(); memset(mem, 0xa5, POOL); mtl_pool_add(mem, POOL);
    pool_t pool = {.magic = MAGIC('P','O','O','L'), .mem = mem, .size = POOL, .flags = NVN_MEMORY_POOL_FLAGS_CPU_CACHED | NVN_MEMORY_POOL_FLAGS_GPU_CACHED};
    tex_t t = {.magic = MAGIC('T','E','X',0), .serial = 996000 + off, .pool = &pool, .mem = mem + off, .off = off};
    t.d = (nvn_texdesc){.target = NVN_TEXTURE_TARGET_BUFFER, .format = NVN_FORMAT_R32UI, .flags = NVN_TEXTURE_FLAGS_IMAGE, .width = N, .height = 1, .depth = 1, .levels = 1, .samples = 1};
    nvn_tex_layout(&t.d, &t.L); mtl_tex_init(&t); mtl_reg_image(600, &t, NULL); mtl_reg_tex(601, &t, NULL);
    int on = tbuf_writeback(); uint32_t *guest = (uint32_t *)(mem + off), *before = (uint32_t *)(mem + 4096), *after = (uint32_t *)(mem + 8192);
    for (int round = 0; round < 2; round++) {
        memset(mem, 0xa5, off + N * 4 + 16);
        for (int i = 0; i < N; i++) guest[i] = 0x12340000u + i;
        memset(before, 0, N * 4); memset(after, 0, N * 4);
        state_reset(); mtl_sub_begin(); CHECK(!g_tbw.n, "a new submission starts without the previous image copies");
        S.ssbo[5][0] = (p_bind_buf){.addr = (uint64_t)before, .size = N * 4};
        S.tex[5][0] = 601;
        // A sampled bind before image preparation used the read shadow; preparing the writable image must replace it, even on a different stage / descriptor of the same serial.
        os_unfair_lock_lock(&g_rmu); void *sampled; uint64_t srid = tex_fast_rid(601, &sampled);
        id<MTLTexture> old = tbuf_shadow((__bridge id<MTLTexture>)sampled, &srid); os_unfair_lock_unlock(&g_rmu);
        NvProg *pr = [NvProg new];
        for (int st = 0; st < 6; st++) { pr->sh[st] = writer; S.img[st][0] = 600; }
        image_prepare(pr, 0x3f);
        CHECK(g_npost == (on ? 1 : 0), "one completion copy per serial, shared by every stage");
        os_unfair_lock_lock(&g_rmu); uint64_t rid; int real; id<MTLTexture> image = img_binding(600, &writer->rf.b[0], &rid, &real);
        CHECK(real && image && (image.usage & MTLTextureUsageShaderWrite), "host binds a writable R32Uint image buffer");
        CHECK(on ? !(image.bufferOffset & 15) && image != old : image.bufferOffset == off, "writeback selects an aligned view; the switch restores the guest offset");
        srid = tex_fast_rid(601, &sampled);
        CHECK(!on || (srid == rid && tbuf_shadow((__bridge id<MTLTexture>)sampled, &srid) == image), "sampled bindings use the same copy, bypassing the stale read shadow");
        os_unfair_lock_unlock(&g_rmu);
        int count = N - round; run_kernel(writer, wp, count);   // the second round leaves the last element untouched: copy-in and copy-back cover the whole view
        S.ssbo[5][0].addr = (uint64_t)after; args_dirty_all(); run_kernel(reader, rp, N);
        if (on) {
            CHECK(guest[0] == 0x12340000u, "encoding has not published shader writes to the guest");
            tbuf_wb *m = g_post[0].vis; id<MTLBuffer> retained = (__bridge id<MTLBuffer>)m->buf;
            CHECK(tbuf_stage(TBS_BLOCK + 256) && g_tbs_blk != retained, "staging rollover keeps the completion snapshot's old buffer");
        }
        CHECK(mtl_wait(mtl_sub_commit(), 5000000000ull), "GPU submission and its completion copies finish");
        CHECK(!mtl_last_commit_error(), "GPU reports no error");
        int values = 1, copied = 1, sampled_ok = 1;
        for (int i = 0; i < N; i++) {
            uint32_t want = i < count ? (uint32_t)i + 1 : 0x12340000u + i;
            if (on) { values &= guest[i] == want; copied &= i >= count || before[i] == 0x12340000u + i; /* a thread that did not run read nothing */ sampled_ok &= after[i] == want; }
        }
        if (on) {
            CHECK(values, "completion writes each element back at its guest address and preserves the untouched element");
            CHECK(copied, "the shader reads the CPU's whole-view copy-in before writing");
            CHECK(sampled_ok, "a later sampled GPU reader sees the image writes in the same submission");
            int guards = 1; for (unsigned i = 0; i < off; i++) guards &= mem[i] == 0xa5;
            for (unsigned i = off + N * 4; i < off + N * 4 + 16; i++) guards &= mem[i] == 0xa5;
            CHECK(guards, "copy-back leaves prefix and row-padding bytes intact");
        } else {
            int shifted = 1; for (int i = 0; i < count; i++) shifted &= ((uint32_t *)mem)[i] == (uint32_t)i + 1;
            CHECK(shifted && guest[0] != 1, "disabled writeback documents stores shifted to the boundary below");
            printf("offset %u: disabled stores land %u bytes early\n", off, off);
        }
    }
    mtl_tex_release(&t); mtl_pool_del(mem); mtl_drain(); free(mem);
}
int main(int argc, char **argv) { @autoreleasepool {
    if (argc == 2 && !strcmp(argv[1], "--post")) return completion_cases();
    mtl_init(); NSError *error = nil;
    id<MTLLibrary> lib = [g_dev newLibraryWithSource:@"#include <metal_stdlib>\nusing namespace metal;\n"
        "struct W { texture_buffer<uint, access::read_write> image [[id(0)]]; device uint *out [[id(1)]]; };\n"
        "struct R { texture_buffer<uint> image [[id(0)]]; device uint *out [[id(1)]]; };\n"
        "kernel void put(constant W &a [[buffer(0)]], uint i [[thread_position_in_grid]]) { a.out[i] = a.image.read(i).x; a.image.write(uint4(i + 1), i); }\n"
        "kernel void get(constant R &a [[buffer(0)]], uint i [[thread_position_in_grid]]) { a.out[i] = a.image.read(i).x; }\n" options:nil error:&error];
    CHECK(lib != nil, "image writer and sampled reader compile"); if (!lib) { fprintf(stderr, "%s\n", error.localizedDescription.UTF8String); return 1; }
    writer = [NvShader new]; reader = [NvShader new]; writer->fn = [lib newFunctionWithName:@"put"]; reader->fn = [lib newFunctionWithName:@"get"];
    CHECK(writer->fn && reader->fn, "image writer and sampled reader functions found"); if (!writer->fn || !reader->fn) return 1;
    for (NvShader *sh in @[writer, reader]) {
        sh->stage = 5; sh->ae = [sh->fn newArgumentEncoderWithBufferIndex:0]; sh->arg_len = sh->ae.encodedLength; sh->rf.nb = 2;
        sh->rf.b[0] = (nvn_rbind){.kind = sh == writer ? NVN_RB_IMG : NVN_RB_TBUF, .aid = 0, .reg = 0, .rw = sh == writer, .dtt = MTLTextureTypeTextureBuffer, .dpf = NVN_DPF_UINT};
        sh->rf.b[1] = (nvn_rbind){.kind = NVN_RB_SBUFP, .aid = 1, .reg = 0, .rw = 1};
    }
    wp = [g_dev newComputePipelineStateWithFunction:writer->fn error:&error]; rp = [g_dev newComputePipelineStateWithFunction:reader->fn error:&error];
    CHECK(wp && rp, "compute pipelines compile"); if (!wp || !rp) return 1;
    image_case(4); image_case(8); image_case(12);
    printf("image buffer writeback (%s): %d checks, %d failed\n", tbuf_writeback() ? "on" : "off", checks, fails); return fails != 0;
} }
