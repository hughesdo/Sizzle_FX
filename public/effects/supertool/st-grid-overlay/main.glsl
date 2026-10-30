// Imported from SuperTool effects/GridOverlay.glsl by scripts/import-supertool.mjs
// Grid Overlay
// Pulsing grid pattern with audio-reactive brightness; additive overlay.
// Ported from DISCO-GLSL-Video-Processor (Shaders/GridOverlay.glsl)
// DISCO sampled an audio texture; here general energy comes from audioRMS().

uniform float gridSize;
uniform float lineThickness;
uniform float gridIntensity;
uniform float audioBoost;
uniform vec3 gridColor;

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;

    vec3 videoCol = texture(iChannel0, uv).rgb;

    float audio = audioRMS();

    vec2 grid = fract(uv * gridSize);
    float pattern = step(1.0 - lineThickness, grid.x) + step(1.0 - lineThickness, grid.y);

    vec3 gridCol = vec3(pattern) * gridIntensity * (0.5 + audio * audioBoost);
    gridCol *= gridColor;

    vec3 col = videoCol + gridCol * 0.5;

    fragColor = vec4(col, 1.0);
}
