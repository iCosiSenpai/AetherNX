// Physical controllers only: GameController's face buttons are named A (bottom), B (right), X (left), Y (top).
#pragma once
#include <math.h>
#include <string.h>
#include "dm_input.h"

static inline int pad_is_nintendo(const char *category, const char *vendor) {
    if (category && (strstr(category, "Joy-Con") || strstr(category, "JoyCon") || strstr(category, "Switch Pro Controller"))) return 1;
    return vendor && ((strstr(vendor, "Nintendo") && strstr(vendor, "Pro Controller")) || strstr(vendor, "Joy-Con") || strstr(vendor, "JoyCon") || !strcmp(vendor, "Pro Controller"));
}

static inline uint64_t pad_map_buttons(int a, int b, int x, int y, int label, int nintendo) {
    if (label && !nintendo) return (a ? DM_BTN_A : 0) | (b ? DM_BTN_B : 0) | (x ? DM_BTN_X : 0) | (y ? DM_BTN_Y : 0);
    return (b ? DM_BTN_A : 0) | (a ? DM_BTN_B : 0) | (y ? DM_BTN_X : 0) | (x ? DM_BTN_Y : 0);
}
static inline float pad_deadzone_value(float d) { return isfinite(d) ? fminf(0.3f, fmaxf(0, d)) : 0; }
static inline void pad_map_stick(float *x, float *y, float deadzone) {
    float d = pad_deadzone_value(deadzone), r = hypotf(*x, *y);
    if (r <= d) { *x = *y = 0; return; }
    if (!d) return;   // zero keeps today's input, including the corners of a square stick
    float scale = (fminf(r, 1) - d) / ((1 - d) * r);
    *x *= scale; *y *= scale;
}
static inline void pad_player_color(int p, float rgb[3]) {
    static const float colors[DM_PLAYERS][3] = {{0,0.3f,1}, {1,0.1f,0.1f}, {0.1f,1,0.2f}, {1,0.4f,0}, {0.7f,0.1f,1}, {0,1,1}, {1,0.2f,0.6f}, {1,1,1}};
    for (int i = 0; i < 3; i++) rgb[i] = colors[p >= 0 && p < DM_PLAYERS ? p : 0][i];
}
