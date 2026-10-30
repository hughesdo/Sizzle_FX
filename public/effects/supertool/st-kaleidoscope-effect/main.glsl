// Imported from SuperTool effects/Kaleidoscope.glsl by scripts/import-supertool.mjs
// Kaleidoscope
// Radial mirror symmetry; segment count is audio-reactive.
// Ported from DISCO-GLSL-Video-Processor (Effects/Kaleidoscope.glsl)
// DISCO sampled audio via iChannel1; here it comes from the bass band.

uniform float baseSegments;
uniform float audioSegments;
uniform float rotation;
uniform float rotationSpeed;
uniform float zoom;

#define PI 3.14159265359

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;

    // Audio (DISCO sampled a low-frequency bin -> bass band here)
    float audio = audioBand(20.0, 250.0);

    // Center, aspect-correct, and zoom
    vec2 centered = (uv * 2.0 - 1.0) * vec2(iResolution.x / iResolution.y, 1.0) * zoom;

    float angle = atan(centered.y, centered.x) + rotation + iTime * rotationSpeed;
    float radius = length(centered);

    // Audio-reactive segment count
    float segments = baseSegments + audio * audioSegments;
    angle = mod(angle, PI * 2.0 / segments);

    // Mirror every other segment
    if (mod(floor(atan(centered.y, centered.x) / (PI * 2.0 / segments)), 2.0) == 1.0) {
        angle = PI * 2.0 / segments - angle;
    }

    vec2 newUv = vec2(cos(angle), sin(angle)) * radius;
    newUv = newUv * 0.5 + 0.5;

    fragColor = texture(iChannel0, newUv);
}
