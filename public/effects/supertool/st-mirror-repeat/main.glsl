// Imported from SuperTool effects/MirrorRepeat.glsl by scripts/import-supertool.mjs
// Mirror Repeat
// Kaleidoscopic polar mirror; segment count and rotation are audio-reactive.
// Ported from DISCO-GLSL-Video-Processor (Effects/MirrorRepeat.glsl)
// DISCO sampled audio via iChannel1; here bass/general come from the FFT helpers.

uniform float baseSegments;
uniform float audioSegments;
uniform float baseRotation;
uniform float audioRotation;
uniform float centerX;
uniform float centerY;

mat2 rot(float a) {
    return mat2(cos(a), -sin(a), sin(a), cos(a));
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;

    float audio = audioRMS();
    float bass = audioBand(20.0, 250.0);

    vec2 center = vec2(centerX, centerY);
    vec2 delta = uv - center;

    float angle = baseRotation + bass * audioRotation;
    delta = rot(angle) * delta;

    float segments = baseSegments + floor(audio * audioSegments);

    float radius = length(delta);
    float theta = atan(delta.y, delta.x);

    float segmentAngle = 6.28318 / segments;
    theta = mod(theta, segmentAngle);

    if (mod(floor(theta / segmentAngle * segments), 2.0) > 0.5) {
        theta = segmentAngle - theta;
    }

    vec2 mirroredUv = center + vec2(cos(theta), sin(theta)) * radius;

    vec3 col = texture(iChannel0, mirroredUv).rgb;
    fragColor = vec4(col, 1.0);
}
