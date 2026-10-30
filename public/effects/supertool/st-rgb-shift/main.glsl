// Imported from SuperTool effects/RGBShift.glsl by scripts/import-supertool.mjs
// RGB Shift Wave
// Wavy RGB channel separation with audio reactivity.
// Ported from DISCO-GLSL-Video-Processor (Effects/RGBShift.glsl)
// DISCO fed bass/mid/treble host uniforms; here audio is the FFT-band average.

uniform float waveFrequency;
uniform float waveSpeed;
uniform float baseShift;
uniform float audioShift;

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;

    // Combined audio energy (replaces DISCO's bassLevel/midLevel/trebleLevel)
    float audio = (audioBand(20.0, 250.0) + audioBand(250.0, 4000.0) + audioBand(4000.0, 16000.0)) / 3.0;

    // Audio-reactive horizontal wave
    float wave = sin(uv.y * waveFrequency + iTime * waveSpeed) * (baseShift + audio * audioShift);

    float r = texture(iChannel0, uv + vec2(wave, 0.0)).r;
    float g = texture(iChannel0, uv).g;
    float b = texture(iChannel0, uv - vec2(wave, 0.0)).b;

    fragColor = vec4(r, g, b, 1.0);
}
