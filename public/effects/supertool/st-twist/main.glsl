// Imported from SuperTool effects/Twist.glsl by scripts/import-supertool.mjs
// Twist
// Radial swirl distortion around a movable center, audio-reactive twist amount
// Ported from DISCO-GLSL-Video-Processor (Effects/Twist.glsl)
// DISCO sampled audio via iChannel1; here it comes from the bass band.

uniform float twistStrength;
uniform float audioTwist;
uniform float centerX;
uniform float centerY;
uniform float animationSpeed;

mat2 rot(float a) {
    return mat2(cos(a), -sin(a), sin(a), cos(a));
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;

    // Audio (DISCO sampled a low-frequency bin -> bass band here)
    float audio = audioBand(20.0, 250.0);

    // Twist center
    vec2 center = vec2(centerX, centerY);
    vec2 delta = uv - center;
    float dist = length(delta);

    // Twist angle grows with distance, audio, and time
    float angle = dist * (twistStrength + audio * audioTwist) + iTime * animationSpeed;
    delta = rot(angle) * delta;

    fragColor = texture(iChannel0, center + delta);
}
