// Imported from SuperTool effects/VideoFilters.glsl by scripts/import-supertool.mjs
// Video Filters
// Classic filters: desaturate / invert / chromatic aberration / channel-swap,
// with a quadrant "all" preview mode. Time/audio-independent.
// Ported from DISCO-GLSL-Video-Processor (Effects/VideoFilters.glsl)
// The DISCO source declared bass/mid/treble but never used them, so this is a
// static effect (audioReactive: false).

uniform float filterMode;
uniform float chromaticAmount;
uniform float showDividers;
uniform float dividerWidth;
uniform float saturationAmount;
uniform float invertAmount;
uniform float colorShiftMode;

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;

    vec3 col = texture(iChannel0, uv).rgb;

    if (filterMode < 0.5) {
        // All effects combined in quadrants
        if (uv.x < 0.5 && uv.y > 0.5) {
            float gray = dot(col, vec3(0.299, 0.587, 0.114));
            col = mix(col, vec3(gray), saturationAmount);
        } else if (uv.x > 0.5 && uv.y > 0.5) {
            col = mix(col, 1.0 - col, invertAmount);
        } else if (uv.x < 0.5 && uv.y < 0.5) {
            col.r = texture(iChannel0, uv + vec2(chromaticAmount, 0.0)).r;
            col.b = texture(iChannel0, uv - vec2(chromaticAmount, 0.0)).b;
        } else {
            if (colorShiftMode < 0.5) col = col.brg;
            else if (colorShiftMode < 1.5) col = col.gbr;
            else col = col.rbg;
        }

        if (showDividers > 0.5) {
            float lineWidth = dividerWidth / iResolution.y;
            if (abs(uv.x - 0.5) < lineWidth || abs(uv.y - 0.5) < lineWidth) {
                col = vec3(1.0);
            }
        }
    } else if (filterMode < 1.5) {
        // Desaturate only
        float gray = dot(col, vec3(0.299, 0.587, 0.114));
        col = mix(col, vec3(gray), saturationAmount);
    } else if (filterMode < 2.5) {
        // Invert only
        col = mix(col, 1.0 - col, invertAmount);
    } else if (filterMode < 3.5) {
        // Chromatic only
        col.r = texture(iChannel0, uv + vec2(chromaticAmount, 0.0)).r;
        col.b = texture(iChannel0, uv - vec2(chromaticAmount, 0.0)).b;
    } else {
        // Color shift only
        if (colorShiftMode < 0.5) col = col.brg;
        else if (colorShiftMode < 1.5) col = col.gbr;
        else col = col.rbg;
    }

    fragColor = vec4(col, 1.0);
}
