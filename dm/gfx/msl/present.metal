// The present: the frame drawn into the drawable, cropped (nvn_mtl.m present_pipeline). Crop.opt holds the picture options (present_opts_fill): sharpening (0..1),
// sharp pixels, the sampled texture's texel size. Sharpening is contrast-adaptive: the centre and its four neighbours one texel away, weighted less where the neighbourhood
// already has contrast, so edges do not ring and flat areas do not turn noisy
#include <metal_stdlib>
using namespace metal;
struct V { float4 p [[position]]; float2 uv; };
vertex V vs(uint id [[vertex_id]]) { float2 uv = float2((id << 1) & 2, id & 2); V o; o.p = float4(uv * float2(2, -2) + float2(-1, 1), 0, 1); o.uv = uv; return o; }
struct Crop { float4 rect; float4 edge; float4 opt; };
static float3 tap(texture2d<float> t, sampler s, constant Crop& c, float2 uv) { return t.sample(s, clamp(uv, c.edge.xy, c.edge.zw)).rgb; }
fragment float4 fs(V in [[stage_in]], texture2d<float> t [[texture(0)]], sampler s [[sampler(0)]], constant Crop& c [[buffer(0)]]) {
  float2 uv = in.uv * c.rect.zw + c.rect.xy;
  if (c.opt.y > 0.5) uv = (floor(uv / c.opt.zw) + 0.5) * c.opt.zw;   // sharp pixels: the centre of the texel under this pixel
  float4 m = t.sample(s, clamp(uv, c.edge.xy, c.edge.zw));
  if (c.opt.x <= 0) return m;
  float2 d = c.opt.zw;
  float3 n = tap(t, s, c, uv - float2(0, d.y)), w = tap(t, s, c, uv - float2(d.x, 0)), e = tap(t, s, c, uv + float2(d.x, 0)), so = tap(t, s, c, uv + float2(0, d.y));
  float3 lo = min(m.rgb, min(min(n, w), min(e, so))), hi = max(m.rgb, max(max(n, w), max(e, so)));
  float3 k = sqrt(saturate(min(lo, 1 - hi) / max(hi, 1e-4))) * (-1.0 / mix(8.0, 5.0, c.opt.x));   // little where the neighbourhood already has contrast
  return float4(saturate((m.rgb + (n + w + e + so) * k) / (1 + 4 * k)), m.a);
}
