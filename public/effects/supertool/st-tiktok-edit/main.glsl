// Imported from SuperTool effects/TikTokEdit.glsl by scripts/import-supertool.mjs
// TikTok Edit (After Effects)
// Frenetic time-driven shake + zoom-blur ray smear with a saturation matrix —
// a "TikTok transition" look. Not audio-reactive; driven entirely by iTime.
// Ported from DISCO-GLSL-Video-Processor (Shaders/After EffectsTik Tok Edit.glsl)
// SuperTool intake note: DISCO declared progress/raySamples/saturation/
// baseIntensity/colorShift/waveAmplitude/pulseSpeed but the active code
// explicitly overrides each with hardcoded values ("ignore the uniform"),
// so those dead uniforms were dropped.

#define PI 3.1415926538

float DecreaseLightTransition(float adjustedLighting, float originalLighting, float speed) {
    return pow(4.0, smoothstep(adjustedLighting, originalLighting, sin(iTime * speed)));
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    float actualRaySamples = 140.0 * fract(215.0 - tan(iTime) * 1.28);

    vec2 uv = fragCoord / iResolution.xy;
    float rayScale = 1.0;

    vec2 editUV = 0.4 + (uv.y + tan(iTime * atan(iTime * 8.0))) *
                  sin(uv.x / max(uv.x, 0.001) - 0.32 + tan(sin(iTime * 0.1 * tan(iTime)))) *
                  vec2((uv * 2.0) - 1.0);

    float progress = 500.0 * tan(iTime * 4.245) / iResolution.x - 1.0;

    vec2 displacement = editUV;
    displacement.xy *= atan(progress * PI / 50.0) / sin(iTime + 0.1);

    vec4 col = texture(iChannel0, displacement + uv);

    col *= 0.99 + 0.1 * sin(110.0 * iTime);
    col *= 0.5 + 0.5 * 16.0 * uv.x * uv.y * (1.0 - uv.x) * (1.0 - uv.y);
    col *= DecreaseLightTransition(12.0, 0.0, 2.0);

    for (float i = 0.0; i < actualRaySamples; i++) {
        rayScale -= 0.0002;
        uv -= abs(cos(iTime));
        uv *= rayScale;
        uv += abs(cos(iTime));
        col += smoothstep(0.0, 0.8, texture(iChannel0, displacement + uv) * 0.2);
    }

    float actualSaturation = 0.3;
    vec3 luminance = vec3(0.04, 0.04, 0.04);
    float oneMinusSat = 0.1 - actualSaturation;

    vec3 red = vec3(luminance.x * oneMinusSat) + vec3(actualSaturation, 0.0, 0.0);
    vec3 green = vec3(luminance.y * oneMinusSat) + vec3(0.0, actualSaturation, 0.0);
    vec3 blue = vec3(luminance.z * oneMinusSat) + vec3(0.0, 0.0, actualSaturation);

    mat4 fullSat = mat4(
        red, 0.0,
        green, 0.0,
        blue, 0.0,
        0.0, 0.0, 0.0, 1.0
    );

    fragColor = col * fullSat;
}
