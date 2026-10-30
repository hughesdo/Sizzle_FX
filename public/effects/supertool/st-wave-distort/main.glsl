// Imported from SuperTool effects/WaveDistort.glsl by scripts/import-supertool.mjs
// Wave Distort
// Sine-wave UV displacement; amplitude is audio-reactive.
// Ported from DISCO-GLSL-Video-Processor (Effects/WaveDistort.glsl)
// DISCO sampled audio via iChannel1; here it comes from the bass band.

uniform float waveFrequency;
uniform float waveSpeed;
uniform float baseAmplitude;
uniform float audioAmplitude;
uniform float waveDirection;   // 0=horizontal, 1=vertical

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;

    float audio = audioBand(20.0, 250.0);

    float waveInput = mix(uv.y, uv.x, waveDirection);
    float wave = sin(waveInput * waveFrequency + iTime * waveSpeed) * (baseAmplitude + audio * audioAmplitude);

    if (waveDirection < 0.5) {
        uv.x += wave;
    } else {
        uv.y += wave;
    }

    fragColor = texture(iChannel0, uv);
}
