#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

static float hash21(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

static float vnoise(float2 p) {
    float2 i = floor(p), f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = hash21(i), b = hash21(i + float2(1, 0));
    float c = hash21(i + float2(0, 1)), d = hash21(i + float2(1, 1));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

static float fbm(float2 p) {
    float v = 0.0, a = 0.5;
    for (int i = 0; i < 4; i++) {
        v += a * vnoise(p);
        p = p * 2.03 + float2(17.1, 9.2);
        a *= 0.5;
    }
    return v;
}

// The app's living background. A domain-warped colour field whose three glows come from the
// day's state (recovery / day score), brightest behind the headline number and falling to ink
// lower down so text contrast never depends on the glass above it.
[[ stitchable ]] half4 tide(float2 position, half4 color, float2 size, float time,
                            half4 deep, half4 glowA, half4 glowB, half4 ember, float energy) {
    float2 uv = position / size.y;
    float t = time * 0.045;
    float2 q = float2(fbm(uv * 1.3 + float2(0.0, t)), fbm(uv * 1.3 + float2(5.2, -t * 0.8)));
    float2 r = float2(fbm(uv * 1.7 + 2.0 * q + float2(1.7, 9.2) + t * 0.6),
                      fbm(uv * 1.7 + 2.0 * q + float2(8.3, 2.8) - t * 0.5));
    float f = fbm(uv * 1.1 + 2.2 * r);

    float3 col = float3(deep.rgb);
    col = mix(col, float3(glowA.rgb), smoothstep(0.22, 0.70, f) * 0.92 * energy);
    col = mix(col, float3(glowB.rgb), smoothstep(0.34, 0.80, r.x) * 0.72 * energy);
    col = mix(col, float3(ember.rgb), smoothstep(0.26, 0.58, q.y * f * 1.6) * 0.34 * energy);

    float y = position.y / size.y;
    col *= mix(1.0, 0.50, smoothstep(0.20, 1.0, y));

    float n = hash21(position + fract(time) * 61.0) - 0.5;
    col += n * (1.5 / 255.0);
    return half4(half3(col), 1.0);
}

// Liquid fill for the water vial: a two-wave surface with a lit meniscus. `level` is 0...1.
[[ stitchable ]] half4 waterFill(float2 position, half4 color, float2 size, float time,
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
