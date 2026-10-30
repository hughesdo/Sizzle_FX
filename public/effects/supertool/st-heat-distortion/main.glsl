// Imported from SuperTool effects/HeatDistortion.glsl by scripts/import-supertool.mjs
// Heat Distortion
// Rising heat-shimmer UV warp; strength is audio-reactive.
// Ported from DISCO-GLSL-Video-Processor (Effects/HeatDistortion.glsl)
// DISCO fed bass/mid/treble host uniforms; here they come from the FFT bands.

uniform float heatStrength;
uniform float heatSpeed;
uniform float heatFrequency;
uniform float audioReactivity;
uniform float timeSpeed;
uniform float noiseComplexity;

float noise(vec2 p) {
    return sin(p.x) * sin(p.y);
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;

    float bassLevel = audioBand(20.0, 250.0);
    float midLevel = audioBand(250.0, 4000.0);
    float trebleLevel = audioBand(4000.0, 16000.0);

    float audio = (bassLevel + midLevel + trebleLevel) / 3.0;
    float heat = heatStrength * (1.0 + audio * audioReactivity);

    float t = iTime * heatSpeed * timeSpeed;
    vec2 distortion = vec2(
        noise(vec2(uv.y * heatFrequency * noiseComplexity, t)) * heat,
        noise(vec2(uv.x * heatFrequency * noiseComplexity + 100.0, t * 1.3)) * heat * 0.5
    );

    fragColor = texture(iChannel0, uv + distortion);
}
