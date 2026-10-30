// Imported from SuperTool effects/Rays.glsl by scripts/import-supertool.mjs
// Rays
// Zoom-blur "ray sampling" — accumulates time-pulsed scaled texture samples
// for a streaking light-ray look. Not audio-reactive.
// Ported from DISCO-GLSL-Video-Processor (Shaders/Rays.glsl)
// SuperTool intake note: DISCO declared progress/saturation/baseIntensity/
// colorShift/waveAmplitude/pulseSpeed "for compatibility, even if unused" —
// the active loop only reads raySamples, so the dead uniforms were dropped.

uniform float raySamples;

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;
    float rayScale = 1.0;

    vec4 col = texture(iChannel0, uv);

    for (float i = 0.0; i < raySamples; i++) {
        rayScale -= 0.0002;

        uv -= abs(cos(iTime));
        uv *= rayScale;
        uv += abs(cos(iTime));

        col += smoothstep(0.0, 0.8, texture(iChannel0, uv) * 0.2);
    }

    fragColor = col;
}
