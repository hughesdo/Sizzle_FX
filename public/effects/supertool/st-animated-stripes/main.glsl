// Imported from SuperTool effects/AnimatedStripes.glsl by scripts/import-supertool.mjs
// Animated Stripes
// Moving diagonal stripes with bass-reactive animation; additive overlay.
// Ported from DISCO-GLSL-Video-Processor (Shaders/AnimatedStripes.glsl)
// DISCO sampled an audio texture; here bass/general come from the FFT bands.

uniform float stripeFrequency;
uniform float stripeSpeed;
uniform float bassModulation;
uniform float stripeIntensity;
uniform float audioBoost;
uniform vec3 stripeColor;

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;

    vec3 videoCol = texture(iChannel0, uv).rgb;

    float audio = audioRMS();
    float bass = audioBand(20.0, 250.0);

    float stripes = sin((uv.x + uv.y) * stripeFrequency + iTime * stripeSpeed + bass * bassModulation);
    stripes = stripes * 0.5 + 0.5;
    stripes = pow(stripes, 2.0);
    stripes *= stripeIntensity * (1.0 + audio * audioBoost);

    vec3 stripeCol = vec3(stripes) * stripeColor;

    vec3 col = videoCol + stripeCol * 0.5;

    fragColor = vec4(col, 1.0);
}
