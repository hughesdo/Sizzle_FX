// Imported from SuperTool effects/PulsingDots.glsl by scripts/import-supertool.mjs
// Pulsing Dots
// Grid of dots whose size pulses with audio energy; additive overlay.
// Ported from DISCO-GLSL-Video-Processor (Shaders/PulsingDots.glsl)
// DISCO sampled an audio texture; here general energy comes from audioRMS().

uniform float dotGridSize;
uniform float baseDotSize;
uniform float audioDotSize;
uniform float dotSmoothness;
uniform float dotIntensity;
uniform float audioBoost;
uniform vec3 dotColor;

float circle(vec2 uv, float r, float smoothness) {
    return smoothstep(r, r - smoothness, length(uv));
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;

    vec3 videoCol = texture(iChannel0, uv).rgb;

    float audio = audioRMS();

    vec2 dotUv = uv * dotGridSize;
    vec2 gv = fract(dotUv) - 0.5;

    float size = baseDotSize + audio * audioDotSize;
    float dotMask = circle(gv, size, dotSmoothness);

    vec3 dotCol = vec3(dotMask) * dotColor * dotIntensity * (1.0 + audio * audioBoost);

    vec3 col = videoCol + dotCol * 0.4;

    fragColor = vec4(col, 1.0);
}
