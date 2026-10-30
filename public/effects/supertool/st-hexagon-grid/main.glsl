// Imported from SuperTool effects/HexagonGrid.glsl by scripts/import-supertool.mjs
// Hexagon Grid
// Hexagonal grid pattern with audio-reactive blend over the video.
// Ported from DISCO-GLSL-Video-Processor (Shaders/HexagonGrid.glsl)
// DISCO sampled an audio texture; here general energy comes from audioRMS().

uniform float hexSize;
uniform float hexThickness;
uniform float hexSmoothness;
uniform float hexIntensity;
uniform float audioBoost;
uniform float blendAmount;
uniform vec3 hexColor;

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;

    vec3 videoCol = texture(iChannel0, uv).rgb;

    float audio = audioRMS();

    vec2 hexUv = uv * hexSize;

    vec2 r = vec2(1.0, 1.73);
    vec2 h = r * 0.5;
    vec2 a = mod(hexUv, r) - h;
    vec2 b = mod(hexUv - h, r) - h;

    vec2 gv = length(a) < length(b) ? a : b;
    float d = length(gv);

    float c = smoothstep(hexThickness, hexThickness + hexSmoothness, d);
    c *= hexIntensity * (1.0 + audio * audioBoost);

    vec3 hexCol = vec3(c) * hexColor;

    float alpha = blendAmount + audio * 0.3;
    vec3 col = mix(videoCol, hexCol, alpha);

    fragColor = vec4(col, 1.0);
}
