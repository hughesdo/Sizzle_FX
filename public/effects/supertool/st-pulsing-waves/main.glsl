// Imported from SuperTool effects/PulsingWaves.glsl by scripts/import-supertool.mjs
// Pulsing Waves
// Concentric waves rippling out from center, modulated by audio energy.
// Ported from DISCO-GLSL-Video-Processor (Shaders/PulsingWaves.glsl)
// DISCO sampled an audio texture; here general energy comes from audioRMS().

uniform float waveFrequency;
uniform float waveSpeed;
uniform float audioModulation;
uniform float waveSharpness;
uniform float waveIntensity;
uniform float audioBoost;
uniform float blendAmount;
uniform vec3 waveColor;

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;

    vec3 videoCol = texture(iChannel0, uv).rgb;

    float audio = audioRMS();

    vec2 centeredUv = (uv * 2.0 - 1.0) * vec2(iResolution.x / iResolution.y, 1.0);

    float dist = length(centeredUv);
    float pulse = sin(dist * waveFrequency - iTime * waveSpeed - audio * audioModulation);
    pulse = pulse * 0.5 + 0.5;
    pulse = pow(pulse, waveSharpness);
    pulse *= waveIntensity;

    vec3 pulseCol = vec3(pulse) * waveColor;

    float alpha = blendAmount + audio * audioBoost;
    vec3 col = mix(videoCol, pulseCol, alpha);

    fragColor = vec4(col, 1.0);
}
