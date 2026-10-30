// Imported from SuperTool effects/SpiralPattern.glsl by scripts/import-supertool.mjs
// Spiral Pattern
// Rotating multi-arm spiral blended over the video; audio-reactive intensity.
// Ported from DISCO-GLSL-Video-Processor (Shaders/SpiralPattern.glsl)
// DISCO sampled an audio texture; here general energy comes from audioRMS().

uniform float spiralArms;
uniform float spiralTightness;
uniform float spiralSpeed;
uniform float spiralIntensity;
uniform float audioBoost;
uniform float blendAmount;
uniform vec3 spiralColor;

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;

    vec3 videoCol = texture(iChannel0, uv).rgb;

    float audio = audioRMS();

    vec2 centeredUv = (uv * 2.0 - 1.0) * vec2(iResolution.x / iResolution.y, 1.0);

    float angle = atan(centeredUv.y, centeredUv.x);
    float radius = length(centeredUv);

    float spiral = sin(angle * spiralArms + radius * spiralTightness - iTime * spiralSpeed);
    spiral = spiral * 0.5 + 0.5;
    spiral *= spiralIntensity * (1.0 + audio * audioBoost);

    vec3 spiralCol = vec3(spiral) * spiralColor;

    float alpha = blendAmount + audio * 0.3;
    vec3 col = mix(videoCol, spiralCol, alpha);

    fragColor = vec4(col, 1.0);
}
