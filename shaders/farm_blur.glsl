// Farm look pipeline (src/FarmShader.lua): one separable Gaussian blur
// step, used for every downsampled pass (the soft out-of-focus copies and the
// bloom). 5 linear-filtered taps = a 9-tap Gaussian along `dir`.
// `threshold` > 0 keeps only bright or strongly coloured pixels (bloom
// source: water highlights, ripe markers, flowers); 0 is a plain blur.

uniform vec2 dir;           // step along the blur axis, in source uv
uniform float threshold;    // 0 = plain blur

float luma(vec3 c) { return dot(c, vec3(0.299, 0.587, 0.114)); }

vec3 pick(Image tex, vec2 uv) {
    vec3 c = Texel(tex, uv).rgb;
    if (threshold <= 0.0) return c;
    float peak = max(c.r, max(c.g, c.b));
    float l = max(luma(c), peak * 0.85);
    return c * smoothstep(threshold, threshold + 0.2, l);
}

vec4 effect(vec4 color, Image tex, vec2 uv, vec2 screen_coords) {
    vec3 s = pick(tex, uv) * 0.227027;
    s += (pick(tex, uv + dir * 1.384615) + pick(tex, uv - dir * 1.384615)) * 0.316216;
    s += (pick(tex, uv + dir * 3.230769) + pick(tex, uv - dir * 3.230769)) * 0.070270;
    return vec4(s, 1.0);
}
