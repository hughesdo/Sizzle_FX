// Imported from SuperTool effects/PerspectiveTilt.glsl by scripts/import-supertool.mjs
// Perspective Tilt
// Tilt-shift perspective skew with depth-of-field box blur; audio-reactive tilt.
// Ported from DISCO-GLSL-Video-Processor (Effects/PerspectiveTilt.glsl)
// DISCO sampled audio via iChannel1; here it comes from the bass band.

uniform float baseTiltAngle;
uniform float audioTiltAngle;
uniform float tiltCenter;
uniform float horizontalShift;
uniform float blurIntensity;
uniform float blurStart;
uniform float blurEnd;

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;

    float audio = audioBand(20.0, 250.0);

    float tiltAngle = baseTiltAngle + audio * audioTiltAngle;

    float perspective = (uv.y - tiltCenter) * tiltAngle;
    uv.x += perspective * horizontalShift;

    float dofDist = abs(uv.y - tiltCenter);
    float blur = smoothstep(blurStart, blurEnd, dofDist) * blurIntensity;

    vec3 col = vec3(0.0);
    float total = 0.0;
    for (float x = -2.0; x <= 2.0; x++) {
        for (float y = -2.0; y <= 2.0; y++) {
            vec2 offset = vec2(x, y) * blur * 0.005;
            col += texture(iChannel0, uv + offset).rgb;
            total += 1.0;
        }
    }
    col /= total;

    fragColor = vec4(col, 1.0);
}
