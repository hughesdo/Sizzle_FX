// Imported from SuperTool effects/ChromaticAberration.glsl by scripts/import-supertool.mjs
// Chromatic Aberration — audio-gated, FFT-driven
// Effect is OFF during silence. Fires when audio RMS exceeds threshold.
// Strength and angle driven by FFT frequency data.
// Ported from DISCO-GLSL-Video-Processor (Effects/ChromaticAberration.glsl)

uniform float triggerThreshold;
uniform float audioIntensity;
uniform float offsetAngle;   // base direction in radians
uniform float angleRange;    // how far spectral tilt can swing the angle

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;

    // Gate: smoothly open as audio RMS crosses threshold
    float gate = smoothstep(triggerThreshold, triggerThreshold + 0.15, audioRMS());

    // Early-out: no effect during silence
    if (gate < 0.001) {
        fragColor = texture(iChannel0, uv);
        return;
    }

    // FFT frequency bands for dynamic offset
    float fftBass = texture(iAudioFFT, vec2(0.03, 0.25)).x;
    float fftMid  = texture(iAudioFFT, vec2(0.40, 0.25)).x;
    float fftHigh = texture(iAudioFFT, vec2(0.75, 0.25)).x;

    // Offset magnitude: gated RMS × FFT weighted
    float hitStrength  = gate * audioRMS();
    float fftMagnitude = fftBass * 0.60 + fftMid * 0.30 + fftHigh * 0.10;
    float offsetAmount = hitStrength * audioIntensity * fftMagnitude;

    // Offset direction moves with spectral balance
    float spectralTilt = fftHigh - fftBass;
    float dynamicAngle = offsetAngle + spectralTilt * angleRange;

    vec2 offset = vec2(cos(dynamicAngle), sin(dynamicAngle)) * offsetAmount;

    // RGB channel separation
    float r = texture(iChannel0, uv + offset).r;
    float g = texture(iChannel0, uv).g;
    float b = texture(iChannel0, uv - offset).b;

    fragColor = vec4(r, g, b, 1.0);
}
