// Imported from SuperTool effects/Mosaic.glsl by scripts/import-supertool.mjs
// Mosaic
// Random colored tiles blended with the video; tile size is audio-reactive.
// Ported from DISCO-GLSL-Video-Processor (Effects/Mosaic.glsl)
// DISCO sampled audio via iChannel1; here it comes from the bass band.

uniform float baseTileSize;
uniform float audioTileSize;
uniform float colorIntensity;
uniform float audioBoost;
uniform float videoBlend;
uniform float animationSpeed;

float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;

    float audio = audioBand(20.0, 250.0);

    float tileSize = baseTileSize + audio * audioTileSize;

    vec2 tileUv = floor(uv * tileSize) / tileSize;
    vec2 tileCenter = tileUv + 0.5 / tileSize;

    float r = hash(tileUv);
    float g = hash(tileUv + 1.0);
    float b = hash(tileUv + 2.0);
    vec3 tileColor = vec3(r, g, b) * colorIntensity;

    vec3 videoColor = texture(iChannel0, tileCenter).rgb;

    tileColor.r += sin(iTime * animationSpeed + tileUv.x * 10.0) * 0.5 + 0.5;
    tileColor *= (1.0 + audio * audioBoost);

    vec3 col = mix(tileColor, videoColor * (1.0 + tileColor * 0.5), videoBlend);

    fragColor = vec4(col, 1.0);
}
