// Imported from SuperTool effects/MatrixRain.glsl by scripts/import-supertool.mjs
// Matrix Rain
// Falling green digital-rain columns over a darkened video; audio-reactive.
// Ported from DISCO-GLSL-Video-Processor (Shaders/MatrixRain.glsl)
// DISCO sampled an audio texture; here general energy comes from audioRMS().

uniform float columnDensity;
uniform float fallSpeed;
uniform float characterDensity;
uniform float brightness;
uniform float audioBoost;
uniform float videoDarken;
uniform float rainIntensity;

float hash(float p) {
    return fract(sin(p) * 43758.5453);
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;

    vec3 videoCol = texture(iChannel0, uv).rgb;

    float audio = audioRMS();

    vec2 matrixUv = uv;
    matrixUv.x *= iResolution.x / iResolution.y;
    matrixUv *= columnDensity;

    vec2 id = floor(matrixUv);
    float speed = hash(id.x) * fallSpeed + 1.0;
    float offset = hash(id.x + 1.0) * 100.0;

    float y = fract(matrixUv.y - iTime * speed + offset);
    float bright = y * y * brightness;

    float cell = step(characterDensity, hash(id.x + id.y + floor(iTime * speed)));

    vec3 matrixCol = vec3(0.0, bright * cell * rainIntensity * (1.0 + audio * audioBoost), 0.0);

    vec3 col = videoCol * videoDarken + matrixCol;

    fragColor = vec4(col, 1.0);
}
