// Imported from SuperTool effects/EdgeNeon.glsl by scripts/import-supertool.mjs
// Neon Edge Effect
// Neon-style outlines with audio-reactive colors
// Synthwave aesthetic — bass=red, mid=green, high=blue neon
// Ported from DISCO-GLSL-Video-Processor (Effects/EdgeNeon.glsl)

uniform float edgeThresholdLow;
uniform float edgeThresholdHigh;
uniform float neonIntensity;
uniform float glowLayerCount;
uniform float glowRadius;
uniform float videoDarken;
uniform float bassNeonR;
uniform float midNeonG;
uniform float highNeonB;
uniform vec3  neonBase;

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;
    vec2 pixel = 1.0 / iResolution.xy;

    // Audio
    float bass = max(texture(iAudioFFT, vec2(0.05, 0.25)).x, audioBand(20.0, 250.0));
    float mid = max(texture(iAudioFFT, vec2(0.2, 0.25)).x, audioBand(250.0, 4000.0));
    float high = max(texture(iAudioFFT, vec2(0.4, 0.25)).x, audioBand(4000.0, 16000.0));

    // Original video
    vec3 col = texture(iChannel0, uv).rgb;

    // Sobel edge detection
    vec3 tl = texture(iChannel0, uv + vec2(-pixel.x, pixel.y)).rgb;
    vec3 tr = texture(iChannel0, uv + vec2(pixel.x, pixel.y)).rgb;
    vec3 bl = texture(iChannel0, uv + vec2(-pixel.x, -pixel.y)).rgb;
    vec3 br = texture(iChannel0, uv + vec2(pixel.x, -pixel.y)).rgb;

    vec3 sobelX = -tl + tr - bl + br;
    vec3 sobelY = -tl - tr + bl + br;

    float edge = length(sobelX) + length(sobelY);
    edge = smoothstep(edgeThresholdLow, edgeThresholdHigh, edge);

    // Neon color (audio-reactive)
    vec3 neonColor = neonBase + vec3(
        bass * bassNeonR,
        mid * midNeonG,
        high * highNeonB
    );

    // Multi-layer glow
    vec3 glow = vec3(0.0);
    int layers = int(glowLayerCount);
    for (int i = 1; i <= layers; i++) {
        float radius = float(i) * glowRadius;
        vec3 layer = vec3(0.0);
        float samples = 0.0;

        for (float x = -2.0; x <= 2.0; x++) {
            for (float y = -2.0; y <= 2.0; y++) {
                vec2 offset = vec2(x, y) * pixel * radius;
                vec3 s = texture(iChannel0, uv + offset).rgb;

                float edgeSample = length(abs(s - col));
                layer += edgeSample * neonColor;
                samples += 1.0;
            }
        }

        layer /= samples;
        glow += layer / float(i);
    }

    // Darken original + add bright neon edges
    vec3 finalCol = col * videoDarken + edge * neonColor * neonIntensity + glow;

    fragColor = vec4(finalCol, 1.0);
}
