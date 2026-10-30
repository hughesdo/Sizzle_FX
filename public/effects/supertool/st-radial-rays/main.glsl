// Imported from SuperTool effects/RadialRays.glsl by scripts/import-supertool.mjs
// Radial Rays
// Rotating sunburst rays radiating from center; bass-modulated, audio-boosted.
// Ported from DISCO-GLSL-Video-Processor (Shaders/RadialRays.glsl)
// DISCO sampled an audio texture; here general/bass come from the FFT bands.

uniform float rayCount;
uniform float raySpeed;
uniform float bassModulation;
uniform float rayIntensity;
uniform float centerFade;
uniform float audioBoost;
uniform vec3 rayColor;

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;

    vec3 videoCol = texture(iChannel0, uv).rgb;

    float audio = audioRMS();
    float bass = audioBand(20.0, 250.0);

    vec2 centeredUv = (uv * 2.0 - 1.0) * vec2(iResolution.x / iResolution.y, 1.0);

    float angle = atan(centeredUv.y, centeredUv.x);
    float rays = sin(angle * rayCount + iTime * raySpeed + bass * bassModulation) * 0.5 + 0.5;

    float dist = length(centeredUv);
    float fade = 1.0 / (1.0 + dist * dist * centerFade);

    vec3 rayCol = vec3(rays * fade) * rayIntensity * (1.0 + audio * audioBoost);
    rayCol *= rayColor;

    vec3 col = videoCol + rayCol * audio * 0.5;

    fragColor = vec4(col, 1.0);
}
