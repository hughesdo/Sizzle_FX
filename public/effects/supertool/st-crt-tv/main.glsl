// Imported from SuperTool effects/CRTTV.glsl by scripts/import-supertool.mjs
// CRT TV
// Curved CRT screen with chromatic aberration, scanlines, flicker, vignette,
// phosphor dots and audio-driven static. Bass triggers noise bursts.
// Ported from DISCO-GLSL-Video-Processor (Shaders/CRTTV.glsl)
// DISCO sampled an audio texture; here general/bass come from the FFT bands.

uniform float curvatureAmount;
uniform float chromaticAberration;
uniform float audioAberration;
uniform float scanlineIntensity;
uniform float scanlineCount;
uniform float flickerSpeed;
uniform float flickerIntensity;
uniform float vignetteStrength;
uniform float staticThreshold;
uniform float staticIntensity;
uniform float ghostingAmount;

float hash21(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;

    float audio = audioRMS();
    float bass = audioBand(20.0, 250.0);

    vec2 crtUv = uv * 2.0 - 1.0;
    crtUv *= 1.0 + curvatureAmount * length(crtUv);
    crtUv = crtUv * 0.5 + 0.5;

    if (crtUv.x < 0.0 || crtUv.x > 1.0 || crtUv.y < 0.0 || crtUv.y > 1.0) {
        fragColor = vec4(0.0, 0.0, 0.0, 1.0);
        return;
    }

    float aberration = chromaticAberration + audio * audioAberration;
    vec3 col;
    col.r = texture(iChannel0, crtUv + vec2(aberration, 0.0)).r;
    col.g = texture(iChannel0, crtUv).g;
    col.b = texture(iChannel0, crtUv - vec2(aberration, 0.0)).b;

    float scanline = sin(crtUv.y * iResolution.y * scanlineCount) * 0.5 + 0.5;
    scanline = scanline * scanlineIntensity + (1.0 - scanlineIntensity);
    col *= scanline;

    float flicker = sin(iTime * flickerSpeed + crtUv.y * 10.0) * flickerIntensity + (1.0 - flickerIntensity);
    col *= flicker;

    float phosphor = sin(crtUv.x * iResolution.x * 3.0) * 0.05 + 0.95;
    col *= phosphor;

    vec2 vignetteUv = uv * (1.0 - uv);
    float vignette = vignetteUv.x * vignetteUv.y * 15.0;
    vignette = pow(vignette, 0.3);
    col *= mix(1.0, vignette, vignetteStrength);

    if (bass > staticThreshold) {
        float noise = hash21(crtUv * iTime) * bass * staticIntensity;
        col += noise;
    }

    float globalFlicker = 1.0 + sin(iTime * 100.0) * 0.01;
    col *= globalFlicker;

    vec3 ghost = texture(iChannel0, crtUv + vec2(ghostingAmount, 0.0)).rgb * 0.1;
    col += ghost;

    fragColor = vec4(col, 1.0);
}
