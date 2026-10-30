// Imported from SuperTool effects/Posterize.glsl by scripts/import-supertool.mjs
// Posterize
// Reduces color depth for a retro look; level count is audio-reactive.
// Ported from DISCO-GLSL-Video-Processor (Effects/Posterize.glsl)
// DISCO fed bass/mid/treble host uniforms; here they come from the FFT bands.

uniform float minLevels;
uniform float maxLevels;
uniform float audioControl;

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;

    float bassLevel = audioBand(20.0, 250.0);
    float midLevel = audioBand(250.0, 4000.0);
    float trebleLevel = audioBand(4000.0, 16000.0);

    float audio = (bassLevel + midLevel + trebleLevel) / 3.0;

    // More audio = fewer levels (more posterized)
    float levels = mix(maxLevels, minLevels, audio * audioControl);
    levels = max(2.0, levels);

    vec3 col = texture(iChannel0, uv).rgb;
    col = floor(col * levels) / levels;

    fragColor = vec4(col, 1.0);
}
