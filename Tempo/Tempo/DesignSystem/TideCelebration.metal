#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// The milestone burst: three light rings expand from a point above the middle
// of the screen while thin sparks fly outward and fade. `time` is seconds since
// the celebration began; at about four seconds only a faint glow is left.
// Colours come in as arguments so the burst follows the day's mood.

static float tideBurstHash(float n) {
    return fract(sin(n * 127.1) * 43758.5453);
}

[[ stitchable ]] half4 tideBurst(float2 position, half4 color, float2 size, float time,
                                 half4 accent, half4 warm) {
    float2 center = float2(size.x * 0.5, size.y * 0.34);
    float2 d = position - center;
    float minDim = min(size.x, size.y);
    float r = length(d) / minDim;
    float ang = atan2(d.y, d.x);

    float3 rgb = float3(0.0);
    float alpha = 0.0;

    // Rings
    for (int i = 0; i < 3; i++) {
        float t = time - float(i) * 0.32;
        if (t > 0.0) {
            float radius = t * 0.46;
            float fade = exp(-t * 1.15);
            float ring = exp(-pow((r - radius) * 24.0, 2.0));
            float w = ring * fade * 0.85;
            rgb += float3(accent.rgb) * w;
            alpha += w;
        }
    }

    // Sparks: thin streaks along 40 directions, each with its own speed and length.
    const float sectors = 40.0;
    float a01 = (ang + M_PI_F) / (2.0 * M_PI_F) * sectors;
    float id = floor(a01);
    float h = tideBurstHash(id + 1.0);
    float cell = fract(a01) - 0.5;
    float head = time * (0.32 + 0.55 * h);
    float len = 0.05 + 0.09 * tideBurstHash(id + 17.0);
    float inTail = step(head - len, r) * step(r, head);
    float tail = saturate((r - (head - len)) / len);
    float widthPx = abs(cell) * 2.0 * M_PI_F * r * minDim / sectors;
    float line = smoothstep(2.4, 0.4, widthPx);
    float spark = inTail * tail * line * exp(-time * 0.8) * step(0.25, h);
    rgb += mix(float3(accent.rgb), float3(warm.rgb), h) * spark;
    alpha += spark;

    // Soft glow at the origin
    float glow = exp(-r * 5.5) * exp(-time * 0.95) * 0.5;
    rgb += float3(accent.rgb) * glow;
    alpha += glow;

    alpha = saturate(alpha);
    rgb = min(rgb, float3(alpha));
    return half4(half3(rgb), half(alpha)) * color.a;
}
