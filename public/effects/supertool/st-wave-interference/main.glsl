// Imported from SuperTool effects/WaveInterference.glsl by scripts/import-supertool.mjs
// Wave Interference
// Two-source ripple interference pattern blended over the video.
// Ported from DISCO-GLSL-Video-Processor (Shaders/WaveInterference.glsl)
// DISCO sampled an audio texture; here general energy comes from audioRMS().

uniform float waveFrequency;
uniform float waveSpeed;
uniform float waveSource1X;
uniform float waveSource2X;
uniform float waveIntensity;
uniform float audioBoost;
uniform float blendAmount;
uniform vec3 waveColor;

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;

    vec3 videoCol = texture(iChannel0, uv).rgb;

    float audio = audioRMS();

    vec2 centeredUv = (uv * 2.0 - 1.0) * vec2(iResolution.x / iResolution.y, 1.0);

    float w1 = sin(length(centeredUv - vec2(waveSource1X, 0.0)) * waveFrequency - iTime * waveSpeed);
    float w2 = sin(length(centeredUv + vec2(waveSource2X, 0.0)) * waveFrequency - iTime * waveSpeed);

    float pattern = (w1 + w2) * 0.5;
    pattern = pattern * 0.5 + 0.5;
    pattern *= waveIntensity * (1.0 + audio * audioBoost);

    vec3 interferenceCol = vec3(pattern) * waveColor;

    float alpha = blendAmount + audio * 0.3;
    vec3 col = mix(videoCol, interferenceCol, alpha);

    fragColor = vec4(col, 1.0);
}
