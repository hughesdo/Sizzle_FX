// Imported from SuperTool effects/ColorCycle.glsl by scripts/import-supertool.mjs
// Color Cycle
// Audio-reactive hue cycling tinted over the video.
// Ported from DISCO-GLSL-Video-Processor (Effects/ColorCycle.glsl)
// DISCO fed bass/mid/treble host uniforms; here they come from the FFT bands.

uniform float cycleSpeed;
uniform float audioReactivity;
uniform float spatialFrequency;
uniform float hueRange;
uniform float bassHueShift;
uniform float midSaturation;
uniform float trebleBrightness;
uniform float timeSpeed;

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

    vec3 videoColor = texture(iChannel0, uv).rgb;

    float hue = fract(iTime * cycleSpeed * timeSpeed + uv.x * spatialFrequency * 0.1 + bassLevel * bassHueShift);
    hue *= hueRange;

    float sat = 0.5 + midLevel * midSaturation;
    float val = 0.7 + trebleLevel * trebleBrightness;

    vec3 cycleColor = hsv2rgb(vec3(hue, sat, val));

    float mixAmount = audioReactivity * (bassLevel + midLevel + trebleLevel) / 3.0;
    vec3 col = mix(videoColor, videoColor * cycleColor * 2.0, mixAmount);

    fragColor = vec4(col, 1.0);
}
