// Imported from SuperTool effects/Vortex.glsl by scripts/import-supertool.mjs
// Vortex
// Swirling spiral pattern overlaid on the video, audio-reactive intensity.
// Ported from DISCO-GLSL-Video-Processor (Effects/Vortex.glsl)
// DISCO sampled audio via iChannel1; here it comes from the bass band.

uniform float vortexSpeed;
uniform float vortexFrequency;
uniform float vortexRadius;
uniform float vortexIntensity;
uniform float audioBoost;
uniform float blendMode;   // 0=overlay, 1=multiply, 2=add
uniform vec3  vortexColor;

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;

    vec4 video = texture(iChannel0, uv);

    // Audio (DISCO sampled a low-frequency bin -> bass band here)
    float audio = audioBand(20.0, 250.0);

    // Center-based, aspect-corrected coordinates
    vec2 centered = (uv * 2.0 - 1.0) * vec2(iResolution.x / iResolution.y, 1.0);

    float angle = atan(centered.y, centered.x);
    float radius = length(centered);

    // Spiral pattern
    float vortex = sin(angle * vortexFrequency - radius * vortexRadius + iTime * vortexSpeed);
    vortex = vortex * 0.5 + 0.5;
    vortex *= exp(-radius);
    vortex *= vortexIntensity * (1.0 + audio * audioBoost);

    vec3 vortexCol = vortex * vortexColor;

    // Blend with video
    vec3 result;
    if (blendMode < 0.5) {
        result = video.rgb + vortexCol;             // overlay (additive)
    } else if (blendMode < 1.5) {
        result = video.rgb * (1.0 + vortexCol);      // multiply
    } else {
        result = video.rgb + vortexCol * 0.5;        // soft add
    }

    fragColor = vec4(result, 1.0);
}
