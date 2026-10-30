// Imported from SuperTool effects/ScanningLines.glsl by scripts/import-supertool.mjs
// Scanning Lines
// Animated horizontal scan lines with a retro feel; additive overlay.
// Ported from DISCO-GLSL-Video-Processor (Shaders/ScanningLines.glsl)
// DISCO sampled an audio texture; here general energy comes from audioRMS().

uniform float lineFrequency;
uniform float lineSpeed;
uniform float lineSharpness;
uniform float lineIntensity;
uniform float audioBoost;
uniform vec3 lineColor;

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;

    vec3 videoCol = texture(iChannel0, uv).rgb;

    float audio = audioRMS();

    float lines = sin(uv.y * iResolution.y * lineFrequency + iTime * lineSpeed) * 0.5 + 0.5;
    lines = pow(lines, lineSharpness);
    lines *= lineIntensity * (1.0 + audio * audioBoost);

    vec3 lineCol = vec3(lines) * lineColor;

    vec3 col = videoCol + lineCol * audio * 0.3;

    fragColor = vec4(col, 1.0);
}
