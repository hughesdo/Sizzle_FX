// Imported from SuperTool effects/Trippy.glsl by scripts/import-supertool.mjs
// Trippy
// Swirl + wave distortion with psychedelic per-channel color shifting.
// Ported from DISCO-GLSL-Video-Processor (Effects/Trippy.glsl)
// DISCO fed bass/mid/treble host uniforms; here they come from the FFT bands.

uniform float distortionAmount;
uniform float swirlSpeed;
uniform float waveFrequency;
uniform float colorIntensity;
uniform float timeSpeed;
uniform float trippyMix;

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;
    vec2 center = uv - 0.5;

    float bassLevel = audioBand(20.0, 250.0);
    float midLevel = audioBand(250.0, 4000.0);
    float trebleLevel = audioBand(4000.0, 16000.0);

    // Swirl distortion
    float dist = length(center);
    float angle = atan(center.y, center.x);
    angle += swirlSpeed * iTime * timeSpeed + bassLevel * distortionAmount;

    // Wave distortion
    float wave = sin(dist * waveFrequency - iTime * timeSpeed * 2.0) * 0.1 * midLevel;
    float newDist = dist + wave;

    vec2 distortedUv = vec2(cos(angle), sin(angle)) * newDist + 0.5;

    vec3 col = texture(iChannel0, distortedUv).rgb;

    // Psychedelic color shifting
    col.r += sin(iTime * timeSpeed + trebleLevel * 5.0) * colorIntensity;
    col.g += sin(iTime * timeSpeed * 1.3 + bassLevel * 5.0) * colorIntensity;
    col.b += sin(iTime * timeSpeed * 1.7 + midLevel * 5.0) * colorIntensity;

    vec3 original = texture(iChannel0, uv).rgb;
    col = mix(original, col, trippyMix);

    fragColor = vec4(col, 1.0);
}
