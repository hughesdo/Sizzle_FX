// Imported from SuperTool effects/Webby.glsl by scripts/import-supertool.mjs
// Webby
// Iterative sine/cosine "web" UV warp with a color-wave tint, time-driven.
// Ported from DISCO-GLSL-Video-Processor (Effects/Webby.glsl)
// The DISCO source declared an audio sample but never used it, so this is a
// time-only effect (audioReactive: false).

uniform float webIntensity;
uniform float webFrequency;
uniform float webSpeed;
uniform float timeSpeed;
uniform float horizontalWarp;
uniform float verticalWarp;
uniform float colorPower;
uniform float colorFrequency;

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;

    vec2 p = uv;

    // Webby warping pattern
    for (float i = 1.0; i < 5.0; i++) {
        p.x += webIntensity * 0.1 / i * sin(i * webFrequency * p.y + iTime * webSpeed * timeSpeed) * horizontalWarp;
        p.y += webIntensity * 0.1 / i * cos(i * webFrequency * p.x + iTime * webSpeed * timeSpeed) * verticalWarp;
    }

    vec3 col = texture(iChannel0, p).rgb;

    float colorWave = sin(p.x * colorFrequency + p.y * colorFrequency) * 0.5 + 0.5;
    col *= 1.0 + colorWave * colorPower * 0.3;

    fragColor = vec4(col, 1.0);
}
