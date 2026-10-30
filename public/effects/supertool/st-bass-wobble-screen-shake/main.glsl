// Imported from SuperTool effects/BassWobbleScreenShake.glsl by scripts/import-supertool.mjs
// Bass Wobble Screen Shake
// Wobble/shake effect reactive to bass frequencies
// Perfect for hard bass hits in music videos
// Ported from DISCO-GLSL-Video-Processor (Effects/BassWobbleScreenShake.glsl)

uniform float shakeIntensity;
uniform float wobbleIntensity;
uniform float wobbleFrequency;
uniform float wobbleSpeed;
uniform float chromaticAberration;
uniform float bassThreshold;
uniform float kickThreshold;
uniform float shakeUpdateRate;

float hash21(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;

    // Audio from FFT texture
    float bass = texture(iAudioFFT, vec2(0.05, 0.25)).x;
    float kick = texture(iAudioFFT, vec2(0.02, 0.25)).x;

    // Also blend in standard audio uniforms for responsiveness
    bass = max(bass, audioBand(20.0, 250.0));

    // Threshold for bass hits
    float bassHit = smoothstep(bassThreshold, bassThreshold + 0.5, bass);
    float kickHit = smoothstep(kickThreshold, 1.0, kick);

    // Screen shake with random direction
    vec2 shake = vec2(0.0);
    if (bassHit > 0.1) {
        float shakeTime = floor(iTime * shakeUpdateRate);
        vec2 randomDir = vec2(
            hash21(vec2(shakeTime, 1.0)) * 2.0 - 1.0,
            hash21(vec2(shakeTime, 2.0)) * 2.0 - 1.0
        );
        shake = randomDir * bassHit * shakeIntensity * (1.0 + kickHit * 2.0);
    }

    // Wobble distortion (circular wave from center)
    vec2 center = vec2(0.5);
    vec2 delta = uv - center;
    float dist = length(delta);

    float wobbleFreq = wobbleFrequency + bass * 30.0;
    float wobblePhase = iTime * wobbleSpeed + kickHit * 10.0;
    float wobble = sin(dist * wobbleFreq - wobblePhase) * bassHit * wobbleIntensity;

    vec2 wobbleOffset = normalize(delta + 0.001) * wobble;

    // Combine shake and wobble
    vec2 finalUv = uv + shake + wobbleOffset;

    // Chromatic aberration on heavy bass
    vec3 col;
    if (kickHit > 0.5) {
        float aberration = kickHit * chromaticAberration;
        col.r = texture(iChannel0, finalUv + vec2(aberration, 0.0)).r;
        col.g = texture(iChannel0, finalUv).g;
        col.b = texture(iChannel0, finalUv - vec2(aberration, 0.0)).b;
    } else {
        col = texture(iChannel0, finalUv).rgb;
    }

    fragColor = vec4(col, 1.0);
}
