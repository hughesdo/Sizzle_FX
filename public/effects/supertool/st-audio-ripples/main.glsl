// Imported from SuperTool effects/AudioRipples.glsl by scripts/import-supertool.mjs
// Audio Ripples
// Concentric ripples whose amplitude tracks overall audio energy.
// Ported from DISCO-GLSL-Video-Processor (Effects/AudioRipples.glsl)
// DISCO fed bass/mid/treble host uniforms; here they come from the FFT bands.

uniform float rippleIntensity;
uniform float rippleFrequency;
uniform float rippleSpeed;
uniform float centerX;
uniform float centerY;
uniform float multiRipple;
uniform float timeSpeed;

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;

    float bassLevel = audioBand(20.0, 250.0);
    float midLevel = audioBand(250.0, 4000.0);
    float trebleLevel = audioBand(4000.0, 16000.0);

    float audio = (bassLevel + midLevel + trebleLevel) / 3.0;

    vec2 center = vec2(centerX, centerY);
    float dist = length(uv - center);

    float ripple = sin(dist * rippleFrequency - iTime * rippleSpeed * timeSpeed) * rippleIntensity * 0.02 * (1.0 + audio);

    if (multiRipple > 0.5) {
        ripple += sin(dist * rippleFrequency * 2.0 - iTime * rippleSpeed * timeSpeed * 1.5) * rippleIntensity * 0.01 * (1.0 + bassLevel);
    }

    vec2 offset = normalize(uv - center) * ripple;
    fragColor = texture(iChannel0, uv + offset);
}
