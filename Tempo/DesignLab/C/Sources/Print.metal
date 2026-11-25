#include <SwiftUI/SwiftUI_Metal.h>
#include <metal_stdlib>
using namespace metal;

// Direction C "Poster": print texture, not glow.

static float hash21(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

// Coverage of a rotated halftone screen. radius01: 0 = no ink, >= 1 = solid.
static float screenDots(float2 pos, float cell, float angle, float radius01) {
    float s = sin(angle), c = cos(angle);
    float2 r = float2(c * pos.x - s * pos.y, s * pos.x + c * pos.y) / cell;
    float2 g = fract(r) - 0.5;
    float d = length(g);
    float rad = radius01 * 0.7071;
    float aa = 0.6 / cell;
    return 1.0 - smoothstep(rad - aa, rad + aa, d);
}

// A flat colour block printed with a second ink: a halftone ramp that gets heavier
// toward the bottom edge, plus paper grain. `amount` 0...1, `grain` about 0.03.
[[ stitchable ]] half4 halftone(float2 position, half4 color, float2 size,
                                float cell, float angle, half4 ink, float amount, float grain) {
    float2 uv = position / size;
    float t = clamp((uv.y - 0.30) / 0.70 + (uv.x - 0.5) * 0.30, 0.0, 1.0);
    t = t * t * amount;
    float m = t <= 0.001 ? 0.0 : screenDots(position, cell, angle, t);
    half3 rgb = mix(color.rgb, ink.rgb, half(m) * ink.a);
    float n = (hash21(floor(position * 2.0)) - 0.5) * grain;
    rgb = clamp(rgb + half(n), half3(0.0), half3(1.0));
    return half4(rgb * color.a, color.a);
}

// Mask for the "ink flood" when a set is logged: the block prints upward from the
// bottom edge, dots first, then solid. progress 0...1.
[[ stitchable ]] half4 inkWipe(float2 position, half4 color, float2 size, float progress, float cell) {
    float y = 1.0 - position.y / size.y;
    float front = progress * 1.7 - 0.12;
    float d = (front - y) / 0.38;
    d += sin(position.x / size.x * 9.42) * 0.07;
    float cov = clamp(d, 0.0, 1.0);
    float m = cov >= 1.0 ? 1.0 : (cov <= 0.0 ? 0.0 : screenDots(position, cell, 0.35, cov * 1.3));
    return color * half(m);
}
