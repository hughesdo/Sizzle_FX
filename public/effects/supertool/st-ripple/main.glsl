// Imported from SuperTool effects/Ripple.glsl by scripts/import-supertool.mjs
// Ripple
// Concentric water-ripple displacement from a movable center; audio-reactive.
// Ported from DISCO-GLSL-Video-Processor (Effects/Ripple.glsl)
// DISCO sampled audio via iChannel1; here it comes from the bass band.

uniform float rippleFrequency;
uniform float rippleSpeed;
uniform float baseAmplitude;
uniform float audioAmplitude;
uniform float centerX;
uniform float centerY;

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;

    float audio = audioBand(20.0, 250.0);

    vec2 center = vec2(centerX, centerY);
    float dist = length(uv - center);

    float ripple = sin(dist * rippleFrequency - iTime * rippleSpeed) * (baseAmplitude + audio * audioAmplitude);
    vec2 offset = normalize(uv - center) * ripple;

    fragColor = texture(iChannel0, uv + offset);
}
