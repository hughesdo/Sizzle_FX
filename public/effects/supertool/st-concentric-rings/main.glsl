// Imported from SuperTool effects/ConcentricRings.glsl by scripts/import-supertool.mjs
// Concentric Rings
// Pulsing concentric rings with bass-reactive waves; additive overlay.
// Ported from DISCO-GLSL-Video-Processor (Shaders/ConcentricRings.glsl)
// DISCO sampled an audio texture; here bass/general come from the FFT bands.

uniform float ringFrequency;
uniform float ringSpeed;
uniform float bassModulation;
uniform float ringSharpness;
uniform float ringIntensity;
uniform float audioBoost;
uniform vec3 ringColor;

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;

    vec3 videoCol = texture(iChannel0, uv).rgb;

    float audio = audioRMS();
    float bass = audioBand(20.0, 250.0);

    vec2 centeredUv = (uv * 2.0 - 1.0) * vec2(iResolution.x / iResolution.y, 1.0);

    float dist = length(centeredUv);
    float rings = sin(dist * ringFrequency - iTime * ringSpeed - bass * bassModulation) * 0.5 + 0.5;
    rings = pow(rings, ringSharpness);

    vec3 ringCol = vec3(rings) * ringIntensity * (1.0 + audio * audioBoost);
    ringCol *= ringColor;

    vec3 col = videoCol + ringCol * audio * 0.5;

    fragColor = vec4(col, 1.0);
}
