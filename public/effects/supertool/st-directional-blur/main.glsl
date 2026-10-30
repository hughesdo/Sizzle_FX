// Imported from SuperTool effects/DirectionalBlur.glsl by scripts/import-supertool.mjs
// Directional Blur
// Linear motion blur along an animated, bass-modulated angle; audio-reactive.
// Ported from DISCO-GLSL-Video-Processor (Effects/DirectionalBlur.glsl)
// DISCO sampled audio via iChannel1; here bass/mid come from the FFT helpers.
// blurSamples is declared float and converted to an int loop bound.

uniform float blurAngle;
uniform float angleSpeed;
uniform float baseBlurStrength;
uniform float audioBlurStrength;
uniform float blurSamples;
uniform float audioAngleModulation;

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;

    float bass = audioBand(20.0, 250.0);
    float mid = audioBand(250.0, 4000.0);

    float angle = blurAngle + iTime * angleSpeed + bass * audioAngleModulation;
    vec2 dir = vec2(cos(angle), sin(angle));

    float strength = baseBlurStrength + mid * audioBlurStrength;

    int samples = int(blurSamples);
    vec3 col = vec3(0.0);
    for (int i = 0; i < samples; i++) {
        float t = float(i) / float(samples) - 0.5;
        vec2 offset = dir * t * strength;
        col += texture(iChannel0, uv + offset).rgb;
    }
    col /= float(samples);

    fragColor = vec4(col, 1.0);
}
