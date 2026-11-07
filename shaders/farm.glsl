// Farm post-process pass (src/FarmShader.lua), one pass over the farm's own
// 320x320 canvas: bloom from bright areas, warm sun multiply and drifting
// diagonal light shafts (scaled by daylight), glimmer on very bright pixels
// (ripe-crop markers, pond highlights), and the day-cycle tint last.
// Every strength is a uniform fed from the FARM_FX_* constants; a strength of
// 0 removes that effect only. Sampling stays on the texel grid (nearest
// canvas), so sprite and text edges stay sharp apart from the bloom glow.

uniform float time;
uniform vec2 texel;             // 1 / canvas size
uniform vec3 dayTint;
uniform float daylight;         // 0 at night .. 1 by day
uniform vec3 sunColor;
uniform float sunStrength;
uniform float shaftStrength;
uniform float shaftSpeed;
uniform float bloomStrength;
uniform float bloomThreshold;
uniform float glimmerStrength;
uniform float glimmerThreshold;

float luma(vec3 c) { return dot(c, vec3(0.299, 0.587, 0.114)); }

vec3 brightPart(Image tex, vec2 uv) {
    vec3 c = Texel(tex, uv).rgb;
    return c * smoothstep(bloomThreshold, 1.0, luma(c));
}

float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }

vec4 effect(vec4 color, Image tex, vec2 uv, vec2 screen_coords) {
    vec4 base = Texel(tex, uv);
    vec3 c = base.rgb;

    // bloom: 8 taps at 2 and 4 texels around the pixel
    vec3 b = vec3(0.0);
    vec2 r1 = texel * 2.0;
    vec2 r2 = texel * 4.0;
    b += brightPart(tex, uv + vec2(r1.x, 0.0));
    b += brightPart(tex, uv - vec2(r1.x, 0.0));
    b += brightPart(tex, uv + vec2(0.0, r1.y));
    b += brightPart(tex, uv - vec2(0.0, r1.y));
    b += brightPart(tex, uv + r2 * 0.7071);
    b += brightPart(tex, uv - r2 * 0.7071);
    b += brightPart(tex, uv + vec2(r2.x, -r2.y) * 0.7071);
    b += brightPart(tex, uv + vec2(-r2.x, r2.y) * 0.7071);
    c += b * (bloomStrength / 8.0);

    // sun: warm multiply and soft diagonal shafts drifting over time
    c *= mix(vec3(1.0), sunColor, sunStrength * daylight);
    float d = (uv.x * 0.8 + uv.y * 0.6) * 2.5 - time * shaftSpeed;
    float band = pow(max(0.0, sin(d * 6.2831853)), 8.0);
    c += sunColor * band * shaftStrength * daylight * (1.0 - uv.y * 0.6);

    // glimmer: a few twinkling 2x2 cells, only on very bright pixels
    vec2 cell = floor(uv / texel / 2.0);
    float h = hash(cell + floor(time * 3.0) * 17.0);
    float g = step(0.97, h) * smoothstep(glimmerThreshold, 1.0, luma(base.rgb));
    c += vec3(g) * glimmerStrength;

    // time of day last, so night darkens everything evenly
    c *= dayTint;
    return vec4(c, base.a) * color;
}
