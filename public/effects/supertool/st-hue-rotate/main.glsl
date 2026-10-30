// Imported from SuperTool effects/HueRotate.glsl by scripts/import-supertool.mjs
// Hue Rotation
// Smooth color cycling with audio reactivity
// Rotation speed modulated by combined audio energy
// Ported from DISCO-GLSL-Video-Processor (Effects/HueRotate.glsl)

uniform float rotationSpeed;
uniform float audioIntensity;

vec3 hueShift(vec3 color, float hue) {
    const vec3 k = vec3(0.57735, 0.57735, 0.57735);
    float cosAngle = cos(hue);
    return vec3(color * cosAngle + cross(k, color) * sin(hue) + k * dot(k, color) * (1.0 - cosAngle));
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;

    // Audio-reactive hue rotation
    float audio = (audioBand(20.0, 250.0) + audioBand(250.0, 4000.0) + audioBand(4000.0, 16000.0)) / 3.0;
    float hueAmount = iTime * rotationSpeed + audio * audioIntensity * 6.28318;

    vec3 col = texture(iChannel0, uv).rgb;
    col = hueShift(col, hueAmount);

    fragColor = vec4(col, 1.0);
}
