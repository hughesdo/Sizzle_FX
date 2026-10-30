// Imported from SuperTool effects/ColorWaves.glsl by scripts/import-supertool.mjs
// Color Waves
// Three animated waves drive a hue-shift over the video, tinted by the bands.
// Ported from DISCO-GLSL-Video-Processor (Effects/ColorWaves.glsl)
// DISCO sampled audio via iChannel1; here it comes from the FFT helpers.

uniform float wave1Frequency;
uniform float wave1Speed;
uniform float wave2Frequency;
uniform float wave2Speed;
uniform float wave3Frequency;
uniform float wave3Speed;
uniform float hueIntensity;
uniform float mixAmount;
uniform float colorOverlay;

vec3 hueShift(vec3 color, float shift) {
    const vec3 k = vec3(0.57735, 0.57735, 0.57735);
    float cosAngle = cos(shift);
    return vec3(color * cosAngle + cross(k, color) * sin(shift) + k * dot(k, color) * (1.0 - cosAngle));
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;

    float audio = audioRMS();
    float bass = audioBand(20.0, 250.0);
    float mid = audioBand(250.0, 4000.0);
    float high = audioBand(4000.0, 16000.0);

    vec3 col = texture(iChannel0, uv).rgb;

    float wave1 = sin(uv.x * wave1Frequency + iTime * wave1Speed + bass * 5.0);
    float wave2 = cos(uv.y * wave2Frequency - iTime * wave2Speed + mid * 5.0);
    float wave3 = sin((uv.x + uv.y) * wave3Frequency + iTime * wave3Speed + high * 5.0);

    float combinedWave = (wave1 + wave2 + wave3) / 3.0;
    float hueShiftAmount = combinedWave * 3.14159 * audio * hueIntensity;

    vec3 shiftedCol = hueShift(col, hueShiftAmount);

    float dynamicMix = mixAmount + audio * 0.7;
    col = mix(col, shiftedCol, dynamicMix);

    vec3 freqColor = vec3(bass, mid, high);
    col = mix(col, col * (1.0 + freqColor), audio * colorOverlay);

    fragColor = vec4(col, 1.0);
}
