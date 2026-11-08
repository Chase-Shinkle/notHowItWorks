// Backrooms camcorder post-process (3D scene only; the HUD is drawn after it).
// The scene canvas holds the 4:3 picture. This pass draws the whole window:
//  * outside `rect` (the centred 4:3 area) a heavily blurred, darkened, stretched copy of the frame;
//  * inside it the picture through a small camcorder lens: subtle barrel distortion, soft focus,
//    mild edge chromatic aberration, light bloom, fine grain and a soft edge vignette.
// Colour grade (sickly yellow) is unchanged from before. Nothing scans, tracks or stamps.
// Coordinates come ONLY from texture coords (uv): the canvas is drawn stretched over the whole window, so uv is
// 0..1 across the window. rect is that picture rect NORMALIZED (0..1); winSize is the LOGICAL window size (grain scale).
uniform vec2 texel;      // 1 / scene canvas size in physical pixels
uniform float dpi;       // physical pixels per logical unit (1 normally, 2 on Retina); keeps blur widths constant
uniform vec4 rect;       // picture rect, normalized to the window: x, y, w, h (0..1)
uniform vec2 winSize;    // window size in LOGICAL units (grain cell scale only)
uniform float bloom;     // 0 = off, ~0.25 mild
uniform float vignette;  // 0..1 edge darkening
uniform float time;      // seconds (grain seed)
uniform float sideFill;  // 1 = blurred side fill, 0 = plain dark sides (diagnostic)
uniform float idle;      // 0..1 extra vignette after standing still

// Explicit finite sanitiser. GLSL clamp()/min()/max() are undefined for NaN, so test with ordered
// comparisons: !(x >= 0.0) is true for NaN and negatives (-> 0.0); min() then caps +Inf and large values at hi.
vec3 finite3(vec3 c, float hi) {
    if (!(c.r >= 0.0)) { c.r = 0.0; }
    if (!(c.g >= 0.0)) { c.g = 0.0; }
    if (!(c.b >= 0.0)) { c.b = 0.0; }
    return vec3(min(c.r, hi), min(c.g, hi), min(c.b, hi));
}

// Every scene-canvas read goes through here: UV clamped half a texel inside the canvas (no edge/wrap
// bleed) and the sample passed through finite3 (NaN/negative -> 0, +Inf/huge -> 8).
vec3 scene(Image tex, vec2 uv) {
    vec2 h = texel * 0.5;
    vec3 c = Texel(tex, clamp(uv, h, vec2(1.0) - h)).rgb;
    return finite3(c, 8.0);
}

float hash(vec2 p) {
    p = fract(p * vec2(443.897, 441.423));
    p += dot(p, p.yx + 19.19);
    return fract((p.x + p.y) * p.x);
}

vec3 glow(Image tex, vec2 uv) {
    vec3 sum = vec3(0.0);
    for (int i = 0; i < 8; i++) {
        float a = float(i) * 0.785398;
        vec2 d = vec2(cos(a), sin(a));
        vec3 c1 = scene(tex, uv + d * texel * dpi * 4.0);
        vec3 c2 = scene(tex, uv + d * texel * dpi * 11.0);
        sum += max(c1 - 0.62, 0.0) + max(c2 - 0.62, 0.0);
    }
    return sum / 16.0;
}

// wide ring blur for the side fill (2 rings x 12 taps + centre)
vec3 heavyBlur(Image tex, vec2 uv) {
    vec3 sum = scene(tex, uv);
    for (int i = 0; i < 12; i++) {
        float a = float(i) * 0.5236;
        vec2 d = vec2(cos(a), sin(a));
        sum += scene(tex, uv + d * vec2(0.035, 0.05));
        sum += scene(tex, uv + d * vec2(0.075, 0.10));
    }
    return sum / 25.0;
}

vec3 grade(vec3 c) {
    float luma = dot(c, vec3(0.299, 0.587, 0.114));
    c = mix(vec3(luma), c, 0.92);                 // slightly washed out
    c *= vec3(1.03, 1.0, 0.88);                   // sickly yellow cast
    return (c - 0.5) * 1.06 + 0.5;                // a touch of contrast
}

vec4 effect(vec4 color, Image tex, vec2 uv, vec2 pixel) {
    // pixel (screen_coords) is deliberately NOT used: everything derives from uv (0..1 across the window).
    vec2 lp = (uv - rect.xy) / max(rect.zw, vec2(1e-4));        // 0..1 inside the picture
    bool inside = lp.x >= 0.0 && lp.x <= 1.0 && lp.y >= 0.0 && lp.y <= 1.0;

    if (!inside) {
        if (sideFill < 0.5) { return vec4(0.02, 0.02, 0.02, 1.0); }
        // stretched copy of the whole frame, blurred hard and dark (never black)
        vec3 b = grade(heavyBlur(tex, uv));
        // fade deeper toward the window edge, but keep some colour
        vec2 e = abs(uv - 0.5) * 2.0;
        b *= 0.62 * (1.0 - 0.35 * max(e.x, e.y));
        float g = hash(floor(uv * winSize) + floor(time * 24.0) * 17.3) - 0.5;
        b += g * 0.012;
        return vec4(finite3(b, 1.0), 1.0);
    }

    // barrel distortion (edges squeezed slightly toward the centre)
    vec2 q = lp * 2.0 - 1.0;
    float r2 = dot(q, q);
    vec2 duv = q * (1.0 + 0.07 * r2) / 1.07 * 0.5 + 0.5;

    // soft focus: sharp centre, gently blurred toward the edges
    float edge = smoothstep(0.2, 1.4, r2);
    float rad = (0.9 + 1.6 * edge);
    vec2 ca = q * (0.0010 + 0.0030 * r2);         // chromatic aberration, mostly at the edges
    vec3 sharp = vec3(scene(tex, duv + ca).r, scene(tex, duv).g, scene(tex, duv - ca).b);
    vec3 soft = vec3(0.0);
    for (int i = 0; i < 8; i++) {
        float a = float(i) * 0.785398;
        vec2 d = vec2(cos(a), sin(a)) * texel * dpi * rad;
        soft += vec3(scene(tex, duv + ca + d).r, scene(tex, duv + d).g, scene(tex, duv - ca + d).b);
    }
    soft /= 8.0;
    vec3 c = mix(sharp, soft, 0.45 + 0.2 * edge);

    if (bloom > 0.0) { c += glow(tex, duv) * bloom * 2.0; }
    c = grade(c);

    // soft edge vignette + slow idle vignette
    float v = smoothstep(0.30, 0.95, length(q * vec2(1.0, 0.9)) * 0.72);
    c *= 1.0 - vignette * v;
    c *= 1.0 - idle * 0.55 * smoothstep(0.15, 0.9, v + 0.25 * v);

    // fine subtle grain; masked so true black stays black
    float lum = dot(c, vec3(0.299, 0.587, 0.114));
    float live = smoothstep(0.01, 0.06, lum);
    float g = hash(floor(uv * winSize) + floor(time * 24.0) * 17.3) - 0.5;
    c += g * 0.03 * live;
    return vec4(finite3(c, 1.0), 1.0);
}
