// Imported from SuperTool effects/CheckerboardOverlay.glsl by scripts/import-supertool.mjs
// Checkerboard Overlay
// Rotating two-color checkerboard blended over the video; bass spins it.
// Ported from DISCO-GLSL-Video-Processor (Shaders/CheckerboardOverlay.glsl)
// DISCO sampled an audio texture; here general/bass come from the FFT bands.

uniform float checkerSize;
uniform float rotationSpeed;
uniform float bassRotation;
uniform float blendAmount;
uniform vec3 color1;
uniform vec3 color2;

mat2 rot(float a) {
    return mat2(cos(a), -sin(a), sin(a), cos(a));
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;

    vec3 videoCol = texture(iChannel0, uv).rgb;

    float audio = audioRMS();
    float bass = audioBand(20.0, 250.0);

    vec2 centered = (uv * 2.0 - 1.0) * vec2(iResolution.x / iResolution.y, 1.0);
    vec2 checkerUv = rot(iTime * rotationSpeed + bass * bassRotation) * centered;
    checkerUv *= checkerSize;

    float checker = mod(floor(checkerUv.x) + floor(checkerUv.y), 2.0);

    vec3 checkerCol = mix(color1, color2, checker);
    checkerCol *= audio;

    float alpha = audio * blendAmount;
    vec3 col = mix(videoCol, checkerCol, alpha);

    fragColor = vec4(col, 1.0);
}
