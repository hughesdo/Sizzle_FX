// Imported from SuperTool effects/BarrelDistortion.glsl by scripts/import-supertool.mjs
// Barrel Distortion
// Fisheye/barrel (or pincushion) lens warp from center; audio-reactive strength.
// Ported from DISCO-GLSL-Video-Processor (Effects/BarrelDistortion.glsl)
// DISCO sampled audio via iChannel1; here it comes from the bass band.

uniform float baseStrength;   // positive=barrel, negative=pincushion
uniform float audioStrength;
uniform float centerX;
uniform float centerY;

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;

    float audio = audioBand(20.0, 250.0);

    vec2 center = vec2(centerX, centerY);
    vec2 delta = uv - center;

    float strength = baseStrength + audio * audioStrength;
    float dist = length(delta);

    float distortedDist = dist * (1.0 + strength * dist * dist);
    vec2 distortedUv = center + normalize(delta) * distortedDist;

    vec3 col = texture(iChannel0, distortedUv).rgb;
    fragColor = vec4(col, 1.0);
}
