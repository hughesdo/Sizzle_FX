// Imported from SuperTool effects/StrobeFlash.glsl by scripts/import-supertool.mjs
// Strobe Flash
// Strobe light flashes synced to the kick. WARNING: very intense — use sparingly.
// Ported from DISCO-GLSL-Video-Processor (Shaders/StrobeFlash.glsl)
// DISCO sampled an audio texture; here bass/kick come from the FFT bands.

uniform float strobeThreshold;
uniform float flashSpeed;
uniform float flashIntensity;
uniform float colorInvert;
uniform float brightnessPulse;

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;

    float bass = audioBand(20.0, 250.0);
    float kick = audioBand(20.0, 80.0);

    vec3 col = texture(iChannel0, uv).rgb;

    float strobe = step(strobeThreshold, kick);

    float flash = mod(floor(iTime * flashSpeed), 2.0);
    flash *= strobe;

    if (flash > 0.5) {
        vec3 inverted = 1.0 - col;
        col = mix(col, inverted, colorInvert);

        float flashAmount = (kick - strobeThreshold) / (1.0 - strobeThreshold);
        col = mix(col, vec3(1.0), flashAmount * flashIntensity);
    }

    float pulse = 1.0 + bass * brightnessPulse;
    col *= pulse;

    fragColor = vec4(col, 1.0);
}
