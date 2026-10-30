// Imported from SuperTool effects/VoronoiCells.glsl by scripts/import-supertool.mjs
// Voronoi Cells
// Animated Voronoi cellular pattern with bass-reactive motion; blended overlay.
// Ported from DISCO-GLSL-Video-Processor (Shaders/VoronoiCells.glsl)
// DISCO sampled an audio texture; here bass/general come from the FFT bands.

uniform float cellScale;
uniform float audioCellScale;
uniform float cellAnimation;
uniform float bassAnimation;
uniform float cellIntensity;
uniform float audioBoost;
uniform float blendAmount;
uniform vec3 cellColor;

vec2 hash2(vec2 p) {
    p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
    return fract(sin(p) * 43758.5453);
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;

    vec3 videoCol = texture(iChannel0, uv).rgb;

    float audio = audioRMS();
    float bass = audioBand(20.0, 250.0);

    vec2 voronoiUv = uv * (cellScale + audio * audioCellScale);

    vec2 i_uv = floor(voronoiUv);
    vec2 f_uv = fract(voronoiUv);

    float minDist = 1.0;
    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            vec2 neighbor = vec2(float(x), float(y));
            vec2 point = hash2(i_uv + neighbor);
            point = 0.5 + 0.5 * sin(iTime * cellAnimation + bass * bassAnimation + 6.28 * point);

            float dist = length(neighbor + point - f_uv);
            minDist = min(minDist, dist);
        }
    }

    vec3 cellCol = vec3(minDist) * cellIntensity * (1.0 + audio * audioBoost);
    cellCol *= cellColor;

    float alpha = blendAmount + audio * 0.4;
    vec3 col = mix(videoCol, cellCol, alpha);

    fragColor = vec4(col, 1.0);
}
