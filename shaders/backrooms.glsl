// Backrooms look: ambient + up to MAX_LIGHTS point lights (warm fluorescent
// fixtures, distance falloff) + exponential distance fog, per pixel. Used with
// g3d's vertex shader (g3d.shaderpath), which supplies worldPosition and
// vertexNormal. Pure look: nothing here feeds back into gameplay.
//
// Uniforms (src/BackroomsLook.lua sends them; unused ones may be compiled out):
//   camPos           eye position, for fog distance
//   ambient          rgb light floor on every surface
//   lightCount       number of valid entries below
//   lightPos/Color/Radius   per fixture; colour is premultiplied by intensity and flicker
//   fogColor/fogDensity     exponential fog
//   litFloor         minimum light on gameplay things (plots, crops, pickups, exit);
//                    0 for room surfaces. Also switches off normal-based shading,
//                    since billboards rotate their model but keep the model-space normal.
//   emissive         0..1 self-lit glow (fixture panels, scaled by their flicker)
#define MAX_LIGHTS 8
#define FOG_NEAR 1.5   // m of clear air before the fog starts, so close walls stay crisp

uniform vec3 camPos;
uniform vec3 ambient;
uniform int lightCount;
uniform vec3 lightPos[MAX_LIGHTS];
uniform vec3 lightColor[MAX_LIGHTS];
uniform float lightRadius[MAX_LIGHTS];
uniform vec3 fogColor;
uniform float fogDensity;
uniform float litFloor;
uniform float emissive;
uniform float shaftRim;    // pit/gap shaft panels: z of this shaft's rim
uniform float shaftFade;   // >0: fog colour goes to black over this many m below shaftRim (0 elsewhere)
uniform float sceneDim;   // 1 normally; ~0.05-0.10 during a hard light-flash OFF phase (scales everything)
uniform float unlit;   // >0: output solid black (exit void)

varying vec4 worldPosition;
varying vec3 vertexNormal;

vec4 effect(vec4 color, Image tex, vec2 uv, vec2 pixel) {
    vec4 texel = Texel(tex, uv) * color;
    if (texel.a < 0.1) { discard; }
    if (unlit > 0.0) { return vec4(0.0, 0.0, 0.0, 1.0); }
    vec3 wp = worldPosition.xyz;
    vec3 n = normalize(vertexNormal);
    bool gameplay = litFloor > 0.0;

    vec3 light = ambient;
    for (int i = 0; i < MAX_LIGHTS; i++) {
        if (i >= lightCount) { break; }
        vec3 d = lightPos[i] - wp;
        float dist = length(d);
        float a = clamp(1.0 - dist / lightRadius[i], 0.0, 1.0);
        a *= a;
        // wrapped diffuse so faces turned a little away still pick up light
        float facing = gameplay ? 0.95 : mix(0.35, 1.0, max(dot(n, d / max(dist, 0.001)), 0.0));
        light += lightColor[i] * a * facing;
    }
    // small readability floor only: gameplay things must dim with zone ambient, fog and outages like walls
    if (gameplay) { light = max(light, vec3(litFloor * 0.22)); }

    vec3 rgb = texel.rgb * light;
    rgb = mix(rgb, texel.rgb * 1.6, clamp(emissive, 0.0, 1.0));   // fixture panels glow past white

    rgb *= sceneDim;

    float fog = 1.0 - exp(-fogDensity * max(length(wp - camPos) - FOG_NEAR, 0.0));
    vec3 fc = fogColor;
    if (shaftFade > 0.0) { fc *= 1.0 - clamp((shaftRim - wp.z) / shaftFade, 0.0, 1.0); }   // depth-local, never absolute z
    rgb = mix(rgb, fc * sceneDim, clamp(fog, 0.0, 1.0));
    return vec4(rgb, texel.a);
}
