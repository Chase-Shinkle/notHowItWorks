// Backrooms post-process (3D scene only; the HUD is drawn after it):
// sickly-yellow colour grade, soft vignette and an optional mild bloom.
// Static: no moving focus band, nothing time-dependent.
//   texel     1 / canvas size
//   bloom     0 = off (quality low/medium), ~0.25 mild
//   vignette  0..1 corner darkening
uniform vec2 texel;
uniform float bloom;
uniform float vignette;
uniform float time;      // seconds (BackroomsLook.now)
uniform float idle;      // 0..1 extra vignette after standing still (eases in slowly, out fast)

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
        vec3 c1 = Texel(tex, uv + d * texel * 4.0).rgb;
        vec3 c2 = Texel(tex, uv + d * texel * 11.0).rgb;
        sum += max(c1 - 0.62, 0.0) + max(c2 - 0.62, 0.0);
    }
    return sum / 16.0;
}

vec4 effect(vec4 color, Image tex, vec2 uv, vec2 pixel) {
    // slight VHS horizontal wobble: a slow wave plus a faint per-band jitter
    float row = floor(uv.y * 240.0);
    float wob = sin(uv.y * 9.0 + time * 1.3) * 0.0007 + (hash(vec2(row, floor(time * 8.0))) - 0.5) * 0.0004;
    uv.x += wob;
    vec3 c = Texel(tex, uv).rgb;
    if (bloom > 0.0) { c += glow(tex, uv) * bloom * 2.0; }
    float luma = dot(c, vec3(0.299, 0.587, 0.114));
    c = mix(vec3(luma), c, 0.92);                 // slightly washed out
    c *= vec3(1.03, 1.0, 0.88);                   // sickly yellow cast
    c = (c - 0.5) * 1.06 + 0.5;                   // a touch of contrast
    vec2 q = uv - 0.5;
    float v = smoothstep(0.30, 0.95, length(q * vec2(1.0, 0.9)) * 1.45);
    c *= 1.0 - vignette * v;
    c *= 1.0 - idle * 0.55 * smoothstep(0.15, 0.9, v + 0.25 * v) ;
    // film grain + occasional thin static lines; masked so true black stays black
    float lum = dot(c, vec3(0.299, 0.587, 0.114));
    float live = smoothstep(0.01, 0.06, lum);
    float g = hash(pixel + floor(time * 24.0) * 17.3) - 0.5;
    c += g * 0.045 * live;
    float slot = floor(time * 3.0);
    float lineY = hash(vec2(slot, 3.1));
    float on = step(0.72, hash(vec2(slot, 7.7)));
    float dy = abs(uv.y - lineY);
    float line = on * (1.0 - smoothstep(0.0007, 0.0016, dy));
    c += line * (hash(vec2(floor(pixel.x * 0.5), slot)) * 0.10 + 0.03) * live;
    return vec4(max(c, 0.0), 1.0);
}
