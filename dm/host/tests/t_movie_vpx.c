// Synthetic 16x16 red key frames encoded with ffmpeg's libvpx encoders; no game data.
// Include the real decoder, without registering unrelated SDK hooks in this test.
#include "../hle.h"
#undef HLE_FORCE
#define HLE_FORCE(mangled, why, ret, cname, ...) static ret cname(__VA_ARGS__)
#include "../hle_movie.c"
#include <assert.h>

static const uint8_t vp8[] = {
    0xf0,0x02,0x00,0x9d,0x01,0x2a,0x10,0x00,0x10,0x00,0x00,0x47,0x08,0x85,0x85,0x88,
    0x85,0x84,0x88,0x02,0x02,0x02,0x75,0xaa,0x03,0xf8,0x03,0xfa,0x02,0x0d,0x4d,0x18,
    0x00,0xfe,0xfd,0x6e,0xf3,0xff,0xe3,0x99,0x37,0x30,0xc4,0xff,0x8e,0x6d,0xff,0xf1,
    0x61,0x3c,0x0e,0x28,0xc8,0xff,0xf1,0x51,0x00,
};
static const uint8_t vp9[] = {
    0x82,0x49,0x83,0x42,0x00,0x00,0xf0,0x00,0xf6,0x00,0x38,0x24,0x1c,0x18,0x4a,0x00,
    0x00,0x30,0x60,0x00,0x00,0x10,0xbf,0xff,0xf7,0x1d,0xaf,0xff,0xff,0xff,0x5f,0xdf,
    0xff,0xff,0xff,0xf2,0x2a,0xc0,0x00,
};
static void decode(int type, int format, const uint8_t *packet, int size) {
    mdec_t d = { .type = type, .fmt = format, .w = 16, .h = 16 };
    assert(md_vpx(&d, packet, size, 0) == 1);
    const uint8_t *p = d.out[0].frm;
    if (format == MD_FMT_NV12) {
        assert(d.out[0].cap == 16 * 16 * 3 / 2);
        for (int i = 0; i < 256; i++) assert(abs(p[i] - 81) <= 3);
        for (int i = 256; i < 384; i += 2) { assert(abs(p[i] - 90) <= 3); assert(abs(p[i+1] - 240) <= 3); }
    } else {
        assert(d.out[0].cap == 16 * 16 * 4);
        for (int i = 0; i < 1024; i += 4) assert(p[i] >= 250 && p[i+1] <= 5 && p[i+2] <= 5 && p[i+3] == 255);
    }
    vpx_codec_destroy(&d.vpx);
    free(d.out[0].frm);
}
// The frame step's movie signal (dm_movie_playing): a video picture handed out raises it for MD_PLAYING_NS; an audio output does not
static uint64_t test_now = 1000000000ull;
uint64_t now_ns(void) { return test_now; }
__thread _Atomic int dm_host_work;   // hle_thread.c
__thread int dm_kill_hold;          // hle_thread.c
static void playing(void) {
    static mdec_t video = { .type = MD_TYPE_VP9, .nout = MD_NOUT_VIDEO, .started = 1 }, audio = { .type = MD_TYPE_VORBIS, .nout = MD_NOUT, .started = 1 };
    pthread_mutex_init(&video.mu, NULL); pthread_mutex_init(&audio.mu, NULL);
    void *vs[2] = { NULL, &video }, *as[2] = { NULL, &audio };
    int idx, left; int64_t pts; uint32_t flags;
    assert(!dm_movie_playing());
    audio.outq[0] = 0; audio.noutq = 1;
    assert(!h_movie_AcqOut(as, &idx, &pts, &flags, &left) && idx == 0 && !dm_movie_playing());
    video.outq[0] = 3; video.noutq = 1;
    assert(!h_movie_AcqOut(vs, &idx, &pts, &flags, &left) && idx == 3 && dm_movie_playing());
    test_now += MD_PLAYING_NS - 1; assert(dm_movie_playing());
    assert(h_movie_AcqOut(vs, &idx, &pts, &flags, &left) == MD_NO_OUTPUT && dm_movie_playing());   // no picture ready: nothing handed out, the signal is not renewed
    test_now += 1; assert(!dm_movie_playing());
    puts("movie signal: a video picture raises it for half a second, audio outputs do not");
}
// Vorbis packets as Ogg pages (md_vorbis_open / md_vorbis): a packet of 65025 bytes or more continues on further pages instead of overrunning one page's lacing table.
// Each page is read back as an Ogg reader would: capture pattern, continuation flag, granule -1 until the packet ends, lacing sums, CRC, and the bytes in order
static void ogg_pages(void) {
    static const size_t sizes[] = {0, 3, 254, 255, 65024, 65025, 65280, 200000};
    for (size_t t = 0; t < sizeof sizes / sizeof *sizes; t++) {
        size_t n = sizes[t], cap = ogg_cap(n); uint8_t *pkt = malloc(n + 1), *out = malloc(cap);
        for (size_t i = 0; i < n; i++) pkt[i] = (uint8_t)(i * 131 + 7);
        mdec_t d = {0}; d.ogg_gran = 4242;
        size_t len = ogg_page(&d, out, pkt, n, 1);
        assert(len <= cap);
        size_t at = 0, got = 0; int pages = 0;
        while (at < len) {
            uint8_t *h = out + at; assert(!memcmp(h, "OggS", 4));
            int seg = h[26]; size_t body = 0; for (int i = 0; i < seg; i++) body += h[27 + i];
            assert(h[5] == (pages ? 1 : 2));
            int64_t g; memcpy(&g, h + 6, 8);
            int last = at + 27 + (size_t)seg + body == len;
            assert(g == (last ? 4242 : -1) && (last || h[27 + seg - 1] == 255));
            uint32_t crc; memcpy(&crc, h + 22, 4); memset(h + 22, 0, 4); assert(ogg_crc(h, 27 + (size_t)seg + body) == crc); memcpy(h + 22, &crc, 4);
            assert(!memcmp(h + 27 + seg, pkt + got, body));
            got += body; at += 27 + (size_t)seg + body; pages++;
        }
        assert(got == n && at == len && d.ogg_seq == (uint32_t)pages && pages == (int)((n / 255 + 1 + 254) / 255));
        free(pkt); free(out);
    }
    puts("Ogg pages: packets of 0 to 200000 bytes laced across pages, continued and checksummed");
}

// I420 → NV12 at odd sizes: the chroma rows hold w bytes, and the interleaving must stay inside them (31 × 2 once stored 32 bytes into a 31-byte last row)
static void nv12_odd(void) {
    static const int sizes[][2] = {{31, 2}, {33, 3}, {1, 1}, {47, 5}, {64, 4}};
    for (size_t t = 0; t < sizeof sizes / sizeof *sizes; t++) {
        int w = sizes[t][0], h = sizes[t][1], cw2 = (w + 1) / 2, ch2 = (h + 1) / 2;
        uint8_t *y = malloc((size_t)w * h), *u = malloc((size_t)(cw2 + 16) * ch2), *v = malloc((size_t)(cw2 + 16) * ch2);
        for (int i = 0; i < w * h; i++) y[i] = (uint8_t)(i + 1);
        for (int i = 0; i < (cw2 + 16) * ch2; i++) { u[i] = (uint8_t)(100 + i); v[i] = (uint8_t)(200 - i); }
        vpx_image_t im = {0}; im.d_w = (unsigned)w; im.d_h = (unsigned)h;
        im.planes[0] = y; im.planes[1] = u; im.planes[2] = v; im.stride[0] = w; im.stride[1] = im.stride[2] = cw2 + 16;
        size_t n = (size_t)w * h * 3 / 2; uint8_t *out = malloc(n);   // exactly what md_vpx allocates
        md_nv12(&im, out, w, h);
        for (int r = 0; r < h / 2; r++) for (int x = 0; 2 * x + 1 < w; x++)
            assert(out[(size_t)w * h + (size_t)r * w + 2 * x] == u[r * (cw2 + 16) + x] && out[(size_t)w * h + (size_t)r * w + 2 * x + 1] == v[r * (cw2 + 16) + x]);
        assert(!memcmp(out, y, (size_t)w * h));
        free(y); free(u); free(v); free(out);
    }
    puts("NV12 at odd sizes: chroma interleaved inside each row, nothing past the output");
}

int main(void) {
    nv12_odd();
    ogg_pages();
    playing();
    int w = 0, h = 0;
    assert(!vp8_size(vp8, 9, &w, &h));
    assert(vp8_size(vp8, sizeof vp8, &w, &h) && w == 16 && h == 16);
    for (int format = MD_FMT_ABGR; format <= MD_FMT_NV12; format++) {
        decode(3, format, vp9, sizeof vp9);
        decode(2, format, vp8, sizeof vp8);
    }
    puts("VP8 and VP9 key frames: NV12 and RGBA pixels match");
}
