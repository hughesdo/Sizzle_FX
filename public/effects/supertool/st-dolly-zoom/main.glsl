// Imported from SuperTool effects/DollyZoom.glsl by scripts/import-supertool.mjs
// Dolly Zoom
// Hitchcock vertigo: oscillating zoom + bass-driven rotation + vignette.
// Ported from DISCO-GLSL-Video-Processor (Effects/DollyZoom.glsl)
// DISCO sampled audio via iChannel1; here bass/mid come from the FFT helpers.

uniform float zoomSpeed;
uniform float zoomIntensity;
uniform float rotationIntensity;
uniform float vignetteStrength;
uniform float vignetteSize;
uniform float centerX;
uniform float centerY;

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;

    float bass = audioBand(20.0, 250.0);

    vec2 center = vec2(centerX, centerY);
    vec2 delta = uv - center;

    // Audio-reactive zoom
    float zoom = 1.0 + sin(iTime * zoomSpeed) * zoomIntensity + bass * zoomIntensity;

    // Rotation on bass
    float angle = bass * rotationIntensity;
    float c = cos(angle);
    float s = sin(angle);
    mat2 rotation = mat2(c, -s, s, c);

    vec2 transformedUv = rotation * (delta / zoom) + center;

    vec3 col = texture(iChannel0, transformedUv).rgb;

    // Vignette
    float dist = length(delta);
    float vignette = 1.0 - smoothstep(vignetteSize, vignetteSize + 0.5, dist) * vignetteStrength;
    col *= vignette;

    fragColor = vec4(col, 1.0);
}
