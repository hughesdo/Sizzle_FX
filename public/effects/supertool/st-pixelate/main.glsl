// Imported from SuperTool effects/Pixelate.glsl by scripts/import-supertool.mjs
// Pixelate
// Blocky downsample; pixel size grows with audio.
// Ported from DISCO-GLSL-Video-Processor (Effects/Pixelate.glsl)
// DISCO sampled audio via iChannel1; here it comes from the bass band.

uniform float basePixelSize;
uniform float audioPixelSize;
uniform float aspectRatio;   // 0=square pixels, 1=preserve aspect

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;

    // Audio (DISCO sampled a low-frequency bin -> bass band here)
    float audio = audioBand(20.0, 250.0);

    // Pixel block size
    float pixelSize = basePixelSize + audio * audioPixelSize;

    vec2 pixelScale = vec2(pixelSize);
    if (aspectRatio > 0.5) {
        pixelScale.x *= iResolution.x / iResolution.y;
    }

    vec2 pixelatedUv = floor(uv * iResolution.xy / pixelScale) * pixelScale / iResolution.xy;

    fragColor = texture(iChannel0, pixelatedUv);
}
