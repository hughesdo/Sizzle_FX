// Imported from SuperTool effects/RadialBlur.glsl by scripts/import-supertool.mjs
// Radial Blur
// Center-out streak blur with audio color-shift and vignette.
// Ported from DISCO-GLSL-Video-Processor (Effects/RadialBlur.glsl)
// DISCO sampled audio via iChannel1; here bass/mid come from the FFT helpers.
// blurSamples is declared float (SuperTool sets custom uniforms as float) and
// converted to an int loop bound.

uniform float baseBlurStrength;
uniform float audioBlurStrength;
uniform float blurSamples;
uniform float colorShift;
uniform float vignetteStrength;
uniform float centerX;
uniform float centerY;

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;

    float bass = audioBand(20.0, 250.0);
    float mid = audioBand(250.0, 4000.0);

    vec2 center = vec2(centerX, centerY);
    vec2 dir = uv - center;
    float dist = length(dir);

    float blurStrength = baseBlurStrength + bass * audioBlurStrength;

    int samples = int(blurSamples);
    vec3 col = vec3(0.0);
    for (int i = 0; i < samples; i++) {
        float t = float(i) / float(samples);
        vec2 offset = dir * t * blurStrength;
        col += texture(iChannel0, uv - offset).rgb;
    }
    col /= float(samples);

    // Color shift with audio
    col.rgb = mix(col.rgb, col.gbr, mid * colorShift);

    // Vignette
    col *= 1.0 - dist * vignetteStrength;

    fragColor = vec4(col, 1.0);
}
