// Imported from SuperTool effects/ZoomBlur.glsl by scripts/import-supertool.mjs
// Zoom Blur
// Radial motion-blur "speed lines" scaling out from a center; audio-reactive.
// Ported from DISCO-GLSL-Video-Processor (Effects/ZoomBlur.glsl)
// DISCO sampled audio via iChannel1; here it comes from the bass band.
// blurSamples is declared float and converted to an int loop bound.

uniform float baseStrength;
uniform float audioStrength;
uniform float blurSamples;
uniform float centerX;
uniform float centerY;

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;

    float audio = audioBand(20.0, 250.0);

    vec2 center = vec2(centerX, centerY);
    vec3 col = vec3(0.0);

    float strength = baseStrength + audio * audioStrength;

    int samples = int(blurSamples);
    for (int i = 0; i < samples; i++) {
        float scale = 1.0 + (float(i) / float(samples)) * strength;
        vec2 sampleUv = center + (uv - center) * scale;
        col += texture(iChannel0, sampleUv).rgb;
    }

    fragColor = vec4(col / float(samples), 1.0);
}
