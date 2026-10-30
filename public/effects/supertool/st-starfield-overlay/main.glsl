// Imported from SuperTool effects/StarfieldOverlay.glsl by scripts/import-supertool.mjs
// Starfield Overlay
// Three parallax star layers drifting over the video; stars swell with audio.
// Ported from DISCO-GLSL-Video-Processor (Shaders/StarfieldOverlay.glsl)
// DISCO sampled an audio texture; here general energy comes from audioRMS().

uniform float starDensity;
uniform float starSpeed;
uniform float starSize;
uniform float audioStarSize;
uniform float starIntensity;
uniform float audioBoost;
uniform float blendAmount;

float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;

    vec3 videoCol = texture(iChannel0, uv).rgb;

    float audio = audioRMS();

    vec3 stars = vec3(0.0);

    for (float layer = 0.0; layer < 3.0; layer++) {
        vec2 st = uv * (starDensity + layer * 50.0);
        st.x += iTime * starSpeed * (0.1 + layer * 0.05);

        vec2 id = floor(st);
        vec2 gv = fract(st) - 0.5;

        float n = hash(id + layer);
        if (n > 0.95) {
            float size = starSize * (1.0 + audio * audioStarSize);
            float star = smoothstep(size, 0.0, length(gv));
            stars += vec3(star) * starIntensity * (1.0 + audio * audioBoost);
        }
    }

    vec3 col = videoCol + stars * blendAmount;

    fragColor = vec4(col, 1.0);
}
