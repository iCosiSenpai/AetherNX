// Anisotropic filtering override (DM_ANISO): the least anisotropy a game's mipmapped linear samplers get, 2, 4, 8 or 16; 0 or unset keeps the game's own.
// Textures seen at a slant (floors, roads, walls along the view) keep their detail instead of blurring into the next mip level. Only samplers that already filter linearly
// between texels and read mip levels take it: nearest samplers (pixel art, lookup tables), samplers without mips, depth-compare and min / max reduction samplers keep the
// game's value, as their results would change meaning. Samplers are made once (nvn_mtl.m samp_by_id, hle_vk.m vkCreateSampler), so a change applies at the next start.
#pragma once
#include <stdatomic.h>
#include <stdlib.h>

static inline int dm_aniso_force(void) {
    static _Atomic int v = -1;
    int n = atomic_load(&v);
    if (n < 0) { const char *e = getenv("DM_ANISO"); int a = e ? atoi(e) : 0; n = a == 2 || a == 4 || a == 8 || a == 16 ? a : 0; atomic_store(&v, n); }
    return n;
}
// The anisotropy a sampler gets: the game's own, raised to DM_ANISO where the sampler qualifies (see above)
static inline unsigned dm_aniso_apply(unsigned game, int linear_min, int mipmapped, int compare, int reduction) {
    int f = dm_aniso_force();
    return f > (int)game && linear_min && mipmapped && !compare && !reduction ? (unsigned)f : game;
}
