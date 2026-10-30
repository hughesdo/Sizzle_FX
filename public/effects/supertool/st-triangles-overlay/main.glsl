// Imported from SuperTool effects/TrianglesOverlay.glsl by scripts/import-supertool.mjs
// Triangles Overlay
// Grid of diamond/triangle cells lit by audio; additive blend over video.
// Ported from DISCO-GLSL-Video-Processor (Shaders/TrianglesOverlay.glsl)
// DISCO sampled an audio texture; here general energy comes from audioRMS().

uniform float triangleSize;
uniform float triangleIntensity;
uniform float audioBoost;
uniform float blendAmount;
uniform vec3 triangleColor;

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;

    vec3 videoCol = texture(iChannel0, uv).rgb;

    float audio = audioRMS();

    vec2 triUv = uv * triangleSize;
    vec2 gv = fract(triUv) - 0.5;

    float triangle = step(abs(gv.x) + abs(gv.y), 0.5);
    triangle *= triangleIntensity * (1.0 + audio * audioBoost);

    vec3 triCol = vec3(triangle) * triangleColor;

    vec3 col = videoCol + triCol * audio * blendAmount;

    fragColor = vec4(col, 1.0);
}
