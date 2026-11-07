// Farm composite pass (src/FarmShader.lua). Inputs: the sharp 320x320 scene
// (`tex`), two soft copies made by shaders/farm_blur.glsl at half and quarter
// resolution, and a quarter-resolution bloom. In order:
//   1. tilt-shift depth of field: FIXED on screen y (never follows the
//      farmer): the middle of the play area is fully sharp, easing
//      smoothly into the soft copies toward the top and bottom edges;
//   2. restrained bloom from bright / strongly coloured areas;
//   3. golden sun: warm multiply, a glow from the upper-left corner and
//      diagonal shafts fanning out from it, drifting slowly;
//   4. glimmer on very bright in-focus pixels;
//   5. grade: lifted saturation, gentle vignette;
//   6. the day-cycle tint last, so night darkens everything evenly.
// Every strength is a uniform fed from the FARM_FX_* constants; 0 removes
// that effect only. The HUD and all text are drawn after this pass.

uniform float time;
uniform vec2 texel;             // 1 / canvas size
uniform vec3 dayTint;
uniform float daylight;         // 0 at night .. 1 by day
uniform vec3 sunColor;
uniform float sunStrength;
uniform float sunGlow;
uniform vec2 sunPos;            // uv of the light source (off-screen corner)
uniform float shaftStrength;
uniform float shaftSpeed;
uniform float bloomStrength;
uniform float bloomThreshold;   // used by the bloom blur passes
uniform float glimmerStrength;
uniform float glimmerThreshold;
uniform float tiltStrength;
uniform float focusHalf;        // half height of the fully sharp middle zone (uv)
uniform float focusRamp;        // distance beyond it over which blur reaches its maximum (uv)
uniform float saturation;       // 0 = unchanged
uniform float vignette;
uniform Image nearTex;          // half-res blur
uniform Image farTex;           // quarter-res blur
uniform Image bloomTex;         // quarter-res thresholded blur

float luma(vec3 c) { return dot(c, vec3(0.299, 0.587, 0.114)); }
float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }

// 4-tap bilinear upsample of a low-res blur; `px` = its texel size in uv
vec3 soft(Image t, vec2 uv, vec2 px) {
    vec2 o = px * 0.5, p = vec2(o.x, -o.y);
    return (Texel(t, uv + o) + Texel(t, uv - o) + Texel(t, uv + p) + Texel(t, uv - p)).rgb * 0.25;
}

vec4 effect(vec4 color, Image tex, vec2 uv, vec2 screen_coords) {
    vec4 base = Texel(tex, uv);
    vec3 c = base.rgb;

    // 1. tilt-shift: depends only on screen y. 0 in the middle zone, rising
    // with a smootherstep to tiltStrength at the top and bottom edges
    float t = clamp((abs(uv.y - 0.5) - focusHalf) / focusRamp, 0.0, 1.0);
    float k = t * t * t * (t * (t * 6.0 - 15.0) + 10.0) * tiltStrength;   // smootherstep
    vec3 nearC = soft(nearTex, uv, texel * 2.0);
    vec3 farC = soft(farTex, uv, texel * 4.0);
    c = mix(c, nearC, smoothstep(0.0, 0.6, k));
    c = mix(c, farC, smoothstep(0.35, 1.0, k));

    // 2. bloom
    c += soft(bloomTex, uv, texel * 4.0) * bloomStrength;

    // 3. golden sun
    c *= mix(vec3(1.0), sunColor, sunStrength * daylight);
    vec2 v = (uv - sunPos) * vec2(1.0, 1.0);
    float dist = length(v);
    float ang = atan(v.y, v.x);
    float drift = time * shaftSpeed;
    float r1 = pow(0.5 + 0.5 * sin(ang * 31.0 + sin(ang * 9.0 + drift * 5.0) * 1.6 + drift * 2.0), 4.0);
    float r2 = pow(0.5 + 0.5 * sin(ang * 13.0 - drift * 3.0 + 1.3), 6.0);
    float fall = smoothstep(1.45, 0.25, dist);
    float shaft = (r1 * 0.65 + r2 * 0.6) * fall;
    float glow = smoothstep(1.0, 0.0, dist);
    vec3 light = sunColor * (shaft * shaftStrength + glow * glow * sunGlow) * daylight;
    c = 1.0 - (1.0 - c) * (1.0 - clamp(light, 0.0, 1.0));     // screen blend: no clipping

    // 4. glimmer: a few twinkling 2x2 cells on very bright, in-focus pixels
    vec2 cell = floor(uv / texel / 2.0);
    float h = hash(cell + floor(time * 3.0) * 17.0);
    float g = step(0.97, h) * smoothstep(glimmerThreshold, 1.0, luma(base.rgb)) * (1.0 - k);
    c += vec3(g) * glimmerStrength;

    // 5. grade: saturation lift and vignette
    float l = luma(c);
    c = mix(vec3(l), c, 1.0 + saturation);
    vec2 q = uv - 0.5;
    c *= 1.0 - vignette * smoothstep(0.3, 0.75, length(q));

    // 6. time of day
    c *= dayTint;
    return vec4(clamp(c, 0.0, 1.0), base.a) * color;
}
