// Imported from SuperTool effects/PulseVignette.glsl by scripts/import-supertool.mjs
// Pulse Vignette
// Pulsing vignette that darkens the edges on bass beats — beat emphasis.
// Ported from DISCO-GLSL-Video-Processor (Shaders/PulseVignette.glsl)
// DISCO sampled an audio texture; here bass/kick come from the FFT bands.

uniform float vignetteSize;
uniform float vignetteSoftness;
uniform float pulseIntensity;
uniform float vignetteStrength;
uniform float brightnessPulse;
uniform float flashThreshold;
uniform float flashIntensity;
uniform float vignetteColorR;
uniform float vignetteColorG;
uniform float vignetteColorB;

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;

    float bass = audioBand(20.0, 250.0);
    float kick = audioBand(20.0, 80.0);

    vec3 col = texture(iChannel0, uv).rgb;

    vec2 center = vec2(0.5);
    float dist = length(uv - center);

    float pulse = bass * pulseIntensity;
    float dynamicVignetteSize = vignetteSize - pulse * 0.3;
    float dynamicVignetteSoftness = vignetteSoftness + kick * 0.3;

    float vignette = smoothstep(dynamicVignetteSize, dynamicVignetteSize + dynamicVignetteSoftness, dist);

    vec3 vignetteColor = vec3(0.0);
    if (bass > 0.5) {
        vignetteColor = vec3(
            bass * vignetteColorR,
            bass * vignetteColorG,
            bass * vignetteColorB
        );
    }

    col = mix(col, vignetteColor, vignette * vignetteStrength);

    float brightness = 1.0 + kick * brightnessPulse;
    col *= brightness;

    if (kick > flashThreshold) {
        float flash = (kick - flashThreshold) / (1.0 - flashThreshold);
        col = mix(col, vec3(1.0), flash * flashIntensity);
    }

    fragColor = vec4(col, 1.0);
}
