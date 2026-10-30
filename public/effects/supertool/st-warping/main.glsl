// Imported from SuperTool effects/Warping.glsl by scripts/import-supertool.mjs
// Warping
// Three selectable UV warp modes (sine / multi-layer / radial), time-driven.
// Ported from DISCO-GLSL-Video-Processor (Effects/Warping.glsl)
// The DISCO source declared an audio sample but never used it, so this is a
// time-only effect (audioReactive: false).

uniform float warpMode;
uniform float warpIntensity;
uniform float warpFrequency;
uniform float warpSpeed;
uniform float timeSpeed;
uniform float layer1Amp;
uniform float layer2Amp;
uniform float layer3Amp;
uniform float layer4Amp;

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;

    vec2 warpedUv = uv;
    float t = iTime * timeSpeed * warpSpeed;

    if (warpMode < 0.5) {
        // Sine warp
        warpedUv.x += sin(uv.y * warpFrequency + t) * warpIntensity * 0.1 * layer1Amp;
        warpedUv.y += cos(uv.x * warpFrequency + t) * warpIntensity * 0.1 * layer2Amp;
    } else if (warpMode < 1.5) {
        // Multi-layer warp
        warpedUv.x += sin(uv.y * warpFrequency + t) * warpIntensity * 0.1 * layer1Amp;
        warpedUv.y += cos(uv.x * warpFrequency * 1.3 + t) * warpIntensity * 0.1 * layer2Amp;
        warpedUv.x += sin(uv.y * warpFrequency * 2.1 + t * 1.5) * warpIntensity * 0.05 * layer3Amp;
        warpedUv.y += cos(uv.x * warpFrequency * 1.7 + t * 1.2) * warpIntensity * 0.05 * layer4Amp;
    } else {
        // Radial warp
        vec2 center = uv - 0.5;
        float dist = length(center);
        float angle = atan(center.y, center.x);
        angle += sin(dist * warpFrequency - t) * warpIntensity * layer1Amp;
        warpedUv = vec2(cos(angle), sin(angle)) * dist + 0.5;
    }

    fragColor = texture(iChannel0, warpedUv);
}
