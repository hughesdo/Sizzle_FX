// Imported from SuperTool effects/Bloom.glsl by scripts/import-supertool.mjs
// Bloom
// Soft glow that blooms bright areas above a luma threshold; audio-reactive.
// Ported from DISCO-GLSL-Video-Processor (Effects/Bloom.glsl)
// DISCO sampled audio via iChannel1; here it comes from the bass band.

uniform float baseRadius;
uniform float audioRadius;
uniform float bloomIntensity;
uniform float audioBoost;
uniform float threshold;

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;

    float audio = audioBand(20.0, 250.0);

    vec3 col = texture(iChannel0, uv).rgb;

    float radius = baseRadius + audio * audioRadius;

    vec3 bloom = vec3(0.0);
    float total = 0.0;
    for (float x = -4.0; x <= 4.0; x++) {
        for (float y = -4.0; y <= 4.0; y++) {
            vec2 offset = vec2(x, y) * radius;
            vec3 sampleCol = texture(iChannel0, uv + offset).rgb;
            float brightness = dot(sampleCol, vec3(0.299, 0.587, 0.114));
            if (brightness > threshold) {
                bloom += sampleCol * (brightness - threshold);
            }
            total += 1.0;
        }
    }
    bloom /= total;

    col += bloom * bloomIntensity * (1.0 + audio * audioBoost);

    fragColor = vec4(col, 1.0);
}
