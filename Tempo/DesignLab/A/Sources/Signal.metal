#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

static float hash21(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

// The day-score ring. The arc, its tick scale and its light are all drawn here, so the
// glow is a function of the value: a higher score throws more light, and the head of the arc is hottest.
[[ stitchable ]] half4 signalRing(float2 position, half4 color, float2 size, float progress, float time, half4 accent) {
    const float TAU = 6.28318530718;
    float2 p = position - size * 0.5;
    float R = min(size.x, size.y) * 0.5;
    float r = length(p);
    float a = atan2(p.x, -p.y);
    if (a < 0.0) { a += TAU; }
    float t = a / TAU;

    float ringR = R * 0.76;
    float thick = R * 0.022;
    float d = abs(r - ringR);
    float band = 1.0 - smoothstep(thick - 0.6, thick + 0.6, d);

    float prog = clamp(progress, 0.0, 1.0);
    // Rounded ends: distance to the start and head points of the arc.
    float2 headP = float2(sin(prog * TAU), -cos(prog * TAU)) * ringR;
    float2 startP = float2(0.0, -ringR);
    float capHead = 1.0 - smoothstep(thick - 0.6, thick + 0.6, length(p - headP));
    float capStart = 1.0 - smoothstep(thick - 0.6, thick + 0.6, length(p - startP));
    float inArc = step(t, prog);
    float arc = max(band * inArc, max(capHead, capStart) * step(0.001, prog));

    // Light: falls off from the lit arc, grows toward the head, breathes slowly.
    float past = 1.0 - smoothstep(prog, prog + 0.035, t);
    float along = past * pow(min(t / max(prog, 0.001), 1.0), 1.6);
    float breathe = 0.92 + 0.08 * sin(time * 0.9);
    float halo = exp(-d / (R * 0.085)) * along * (0.25 + 0.75 * prog) * breathe;
    float headGlow = exp(-length(p - headP) / (R * 0.11)) * (0.35 + 0.65 * prog) * breathe;

    // Tick scale inside the ring: 60 marks, every fifth longer.
    float tickIdx = floor(t * 60.0 + 0.5);
    float tickAng = abs(t * 60.0 - tickIdx) / 60.0 * TAU * r;
    float major = step(0.5, 1.0 - fmod(tickIdx, 5.0));
    float tickIn = R * (major > 0.5 ? 0.60 : 0.625);
    float tickOut = R * 0.655;
    float tick = (1.0 - smoothstep(0.45, 1.05, tickAng)) * smoothstep(tickIn - 0.6, tickIn + 0.6, r) * (1.0 - smoothstep(tickOut - 0.6, tickOut + 0.6, r));
    float tickLit = step(tickIdx / 60.0, prog + 0.0001);

    float edge = 1.0 - smoothstep(R * 0.86, R * 0.995, r);
    halo *= edge; headGlow *= edge;
    float trackA = band * (1.0 - inArc) * 0.09;
    float3 acc = float3(accent.rgb);
    float3 rgb = acc * (arc + halo * 0.42 + headGlow * 0.55)
               + float3(1.0) * (trackA + tick * mix(0.13, 0.0, tickLit))
               + acc * tick * tickLit * 0.75
               + float3(1.0) * capHead * 0.35;
    float alpha = clamp(max(rgb.r, max(rgb.g, rgb.b)), 0.0, 1.0);
    return half4(half3(min(rgb, float3(1.0))), half(alpha));
}

// Background: near-black with fine grain and one soft pool of light behind the hero,
// so the blacks have depth instead of being a flat fill.
[[ stitchable ]] half4 signalGrain(float2 position, half4 color, float2 size, float2 light, float amount, half4 accent) {
    float n = hash21(floor(position * 3.0)) - 0.5;
    float pool = exp(-length((position - light) / float2(size.x * 0.75, size.x * 0.6)));
    float3 rgb = float3(color.rgb) + n * amount + float3(accent.rgb) * pool * 0.045 + float3(pool * 0.02);
    return half4(half3(rgb), 1.0);
}

// A lit level bar: filled part glows at its leading edge, the rest is a dim track.
[[ stitchable ]] half4 signalBar(float2 position, half4 color, float2 size, float progress, half4 accent) {
    float x = position.x / size.x;
    float prog = clamp(progress, 0.0, 1.0);
    float lit = 1.0 - smoothstep(prog - 0.5 / size.x, prog + 0.5 / size.x, x);
    float lead = exp(-abs(x - prog) * size.x / 18.0) * lit;
    float3 rgb = float3(accent.rgb) * lit * (0.72 + 0.28 * lead) + float3(1.0) * (1.0 - lit) * 0.09 + float3(1.0) * lead * 0.18;
    float a = max(lit, 0.09);
    return half4(half3(min(rgb, float3(1.0))) * color.a, half(a) * color.a);
}
