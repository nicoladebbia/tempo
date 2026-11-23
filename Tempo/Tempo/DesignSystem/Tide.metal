#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// Tide design system shaders. Every colour comes in as an argument so the
// whole set follows the day's mood (see TideMood).

static float tideHash(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

static float tideNoise(float2 p) {
    float2 i = floor(p), f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = tideHash(i), b = tideHash(i + float2(1, 0));
    float c = tideHash(i + float2(0, 1)), d = tideHash(i + float2(1, 1));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

static float tideFbm(float2 p) {
    float v = 0.0, a = 0.5;
    for (int i = 0; i < 4; i++) {
        v += a * tideNoise(p);
        p = p * 2.03 + float2(17.1, 9.2);
        a *= 0.5;
    }
    return v;
}

// The app background: a slow domain-warped colour field. Brightest behind the
// headline number, falling to ink lower down so text contrast never depends on
// the glass above it.
[[ stitchable ]] half4 tideField(float2 position, half4 color, float2 size, float time,
                                 half4 deep, half4 glowA, half4 glowB, half4 ember, float energy) {
    float2 uv = position / size.y;
    float t = time * 0.045;
    float2 q = float2(tideFbm(uv * 1.3 + float2(0.0, t)), tideFbm(uv * 1.3 + float2(5.2, -t * 0.8)));
    float2 r = float2(tideFbm(uv * 1.7 + 2.0 * q + float2(1.7, 9.2) + t * 0.6),
                      tideFbm(uv * 1.7 + 2.0 * q + float2(8.3, 2.8) - t * 0.5));
    float f = tideFbm(uv * 1.1 + 2.2 * r);

    float3 col = float3(deep.rgb);
    col = mix(col, float3(glowA.rgb), smoothstep(0.22, 0.70, f) * 0.92 * energy);
    col = mix(col, float3(glowB.rgb), smoothstep(0.34, 0.80, r.x) * 0.72 * energy);
    col = mix(col, float3(ember.rgb), smoothstep(0.26, 0.58, q.y * f * 1.6) * 0.34 * energy);

    float y = position.y / size.y;
    col *= mix(1.0, 0.50, smoothstep(0.20, 1.0, y));

    float n = tideHash(position + fract(time) * 61.0) - 0.5;
    col += n * (1.5 / 255.0);
    return half4(half3(col), 1.0);
}

// The score dial: arc, 60-tick scale and light are all drawn here, so the glow
// is a function of the value. A higher score throws more light and the head of
// the arc is hottest.
[[ stitchable ]] half4 tideDial(float2 position, half4 color, float2 size, float progress, float time, half4 accent) {
    const float TAU = 6.28318530718;
    float2 p = position - size * 0.5;
    float R = min(size.x, size.y) * 0.5;
    float r = length(p);
    float a = atan2(p.x, -p.y);
    if (a < 0.0) { a += TAU; }
    float t = a / TAU;

    float ringR = R * 0.76;
    float thick = R * 0.026;
    float d = abs(r - ringR);
    float band = 1.0 - smoothstep(thick - 0.6, thick + 0.6, d);

    float prog = clamp(progress, 0.0, 1.0);
    float2 headP = float2(sin(prog * TAU), -cos(prog * TAU)) * ringR;
    float2 startP = float2(0.0, -ringR);
    float capHead = 1.0 - smoothstep(thick - 0.6, thick + 0.6, length(p - headP));
    float capStart = 1.0 - smoothstep(thick - 0.6, thick + 0.6, length(p - startP));
    float inArc = step(t, prog);
    float arc = max(band * inArc, max(capHead, capStart) * step(0.001, prog));

    float past = 1.0 - smoothstep(prog, prog + 0.035, t);
    float along = past * pow(min(t / max(prog, 0.001), 1.0), 1.6);
    float breathe = 0.92 + 0.08 * sin(time * 0.9);
    float halo = exp(-d / (R * 0.085)) * along * (0.25 + 0.75 * prog) * breathe;
    float headGlow = exp(-length(p - headP) / (R * 0.11)) * (0.35 + 0.65 * prog) * breathe;

    float tickIdx = floor(t * 60.0 + 0.5);
    float tickAng = abs(t * 60.0 - tickIdx) / 60.0 * TAU * r;
    float major = step(0.5, 1.0 - fmod(tickIdx, 5.0));
    float tickIn = R * (major > 0.5 ? 0.60 : 0.625);
    float tickOut = R * 0.655;
    float tick = (1.0 - smoothstep(0.45, 1.05, tickAng)) * smoothstep(tickIn - 0.6, tickIn + 0.6, r)
               * (1.0 - smoothstep(tickOut - 0.6, tickOut + 0.6, r));
    float tickLit = step(tickIdx / 60.0, prog + 0.0001);

    float edge = 1.0 - smoothstep(R * 0.86, R * 0.995, r);
    halo *= edge; headGlow *= edge;
    float trackA = band * (1.0 - inArc) * 0.14;
    float3 acc = float3(accent.rgb);
    float3 rgb = acc * (arc + halo * 0.42 + headGlow * 0.55)
               + float3(1.0) * (trackA + tick * mix(0.20, 0.0, tickLit))
               + acc * tick * tickLit * 0.80
               + float3(1.0) * capHead * 0.35;
    float alpha = clamp(max(rgb.r, max(rgb.g, rgb.b)), 0.0, 1.0);
    return half4(half3(min(rgb, float3(1.0))), half(alpha));
}

// A lit level bar: the filled part glows at its leading edge, the rest is a dim track.
[[ stitchable ]] half4 tideLevel(float2 position, half4 color, float2 size, float progress, half4 accent) {
    float x = position.x / size.x;
    float prog = clamp(progress, 0.0, 1.0);
    float lit = 1.0 - smoothstep(prog - 0.5 / size.x, prog + 0.5 / size.x, x);
    float lead = exp(-abs(x - prog) * size.x / 18.0) * lit;
    float3 rgb = float3(accent.rgb) * lit * (0.72 + 0.28 * lead) + float3(1.0) * (1.0 - lit) * 0.14 + float3(1.0) * lead * 0.18;
    float a = max(lit, 0.14);
    return half4(half3(min(rgb, float3(1.0))) * color.a, half(a) * color.a);
}

// Liquid fill (water vial): a two-wave surface with a lit meniscus. `level` is 0...1.
[[ stitchable ]] half4 tideLiquid(float2 position, half4 color, float2 size, float time,
                                  float level, half4 top, half4 bottom) {
    float x = position.x / size.x;
    float y = position.y / size.y;
    float wave = sin(x * 9.42 + time * 1.6) * 0.014 + sin(x * 17.0 - time * 1.1) * 0.008;
    float surface = 1.0 - level + wave;
    float a = smoothstep(surface - 0.006, surface + 0.006, y);
    float depth = saturate((y - surface) / max(level, 0.001));
    float3 c = mix(float3(top.rgb), float3(bottom.rgb), depth);
    c += smoothstep(0.03, 0.0, abs(y - surface - 0.012)) * 0.30;
    return half4(half3(c), 1.0) * half(a) * color.a;
}
