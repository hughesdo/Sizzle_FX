// Imported from SuperTool effects/DigitalGlitch.glsl by scripts/import-supertool.mjs
// Digital Glitch
// Random scanline displacement + chromatic shift on glitch; audio-reactive.
// Ported from DISCO-GLSL-Video-Processor (Effects/DigitalGlitch.glsl)
// DISCO fed bass/mid/treble host uniforms; here they come from the FFT bands.

uniform float glitchFrequency;
uniform float glitchThreshold;
uniform float displacementAmount;
uniform float chromaticShift;
uniform float audioSensitivity;

float hash(float p) {
    return fract(sin(p) * 43758.5453);
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;

    float bassLevel = audioBand(20.0, 250.0);
    float midLevel = audioBand(250.0, 4000.0);
    float trebleLevel = audioBand(4000.0, 16000.0);

    float audio = (bassLevel + midLevel + trebleLevel) / 3.0;
    float glitch = step(glitchThreshold, hash(floor(iTime * glitchFrequency)));
    glitch *= audio * audioSensitivity;

    float yOffset = hash(floor(uv.y * 100.0 + iTime)) * displacementAmount * glitch;
    uv.x += yOffset;

    vec3 col = texture(iChannel0, uv).rgb;

    if (glitch > 0.5) {
        col.r = texture(iChannel0, uv + vec2(chromaticShift, 0.0)).r;
        col.b = texture(iChannel0, uv - vec2(chromaticShift, 0.0)).b;
    }

    fragColor = vec4(col, 1.0);
}
