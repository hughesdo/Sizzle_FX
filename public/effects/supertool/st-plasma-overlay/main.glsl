// Imported from SuperTool effects/PlasmaOverlay.glsl by scripts/import-supertool.mjs
// Plasma Overlay
// Classic four-wave plasma field blended over the video; bass-modulated.
// Ported from DISCO-GLSL-Video-Processor (Shaders/PlasmaOverlay.glsl)
// DISCO sampled an audio texture; here general/bass come from the FFT bands.

uniform float plasmaScale;
uniform float plasmaSpeed;
uniform float bassModulation;
uniform float plasmaIntensity;
uniform float colorShift;
uniform float blendAmount;
uniform float audioBlend;

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;

    vec3 videoCol = texture(iChannel0, uv).rgb;

    float audio = audioRMS();
    float bass = audioBand(20.0, 250.0);

    vec2 plasmaUv = (uv * 2.0 - 1.0) * vec2(iResolution.x / iResolution.y, 1.0);

    float v = 0.0;
    v += sin(plasmaUv.x * plasmaScale + iTime * plasmaSpeed);
    v += sin(plasmaUv.y * plasmaScale + iTime * plasmaSpeed);
    v += sin((plasmaUv.x + plasmaUv.y) * plasmaScale + iTime * plasmaSpeed);
    v += sin(length(plasmaUv) * plasmaScale + iTime * plasmaSpeed + bass * bassModulation);
    v *= 0.25;

    v = v * 0.5 + 0.5;
    v *= plasmaIntensity;

    vec3 plasmaCol = vec3(
        sin(v * 6.28 + colorShift),
        sin(v * 6.28 + colorShift + 2.09),
        sin(v * 6.28 + colorShift + 4.18)
    ) * 0.5 + 0.5;

    float alpha = blendAmount + audio * audioBlend;
    vec3 col = mix(videoCol, plasmaCol, alpha);

    fragColor = vec4(col, 1.0);
}
