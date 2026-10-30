// Imported from SuperTool effects/ColorCycle2.glsl by scripts/import-supertool.mjs
// Color Cycle 2
// Rainbow cycle + bass vibration + mid pulse + treble flash over the video.
// Ported from DISCO-GLSL-Video-Processor (Effects/ColorCycle2.glsl)
// DISCO fed bass/mid/treble host uniforms; here they come from the FFT bands.

uniform float vibrateIntensity;
uniform float rainbowSpeed;
uniform float rainbowFrequency;
uniform float bassVibration;
uniform float midPulse;
uniform float trebleFlash;
uniform float audioReactivity;
uniform float timeSpeed;
uniform float colorMix;

vec3 hsv2rgb(vec3 c) {
    vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;

    float bassLevel = audioBand(20.0, 250.0);
    float midLevel = audioBand(250.0, 4000.0);
    float trebleLevel = audioBand(4000.0, 16000.0);

    // Vibration offset (audio reactive)
    vec2 vibration = vec2(
        sin(iTime * 50.0 * timeSpeed) * bassLevel * bassVibration,
        cos(iTime * 45.0 * timeSpeed) * bassLevel * bassVibration
    ) * vibrateIntensity * 0.01;

    vec2 vibratedUv = uv + vibration;

    vec3 videoColor = texture(iChannel0, vibratedUv).rgb;

    float rainbow = fract((uv.x + uv.y) * rainbowFrequency * 0.1 + iTime * rainbowSpeed * timeSpeed);
    vec3 rainbowColor = hsv2rgb(vec3(rainbow, 0.8, 1.0));

    float pulse = 1.0 + midLevel * midPulse;
    float flash = trebleLevel * trebleFlash;

    vec3 col = videoColor;
    col = mix(col, col * rainbowColor * 2.0, colorMix * audioReactivity);
    col *= pulse;
    col += flash;

    fragColor = vec4(col, 1.0);
}
