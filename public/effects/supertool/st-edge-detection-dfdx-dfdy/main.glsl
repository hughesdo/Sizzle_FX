// Imported from SuperTool effects/EdgeDetectionDFdxDFdy.glsl by scripts/import-supertool.mjs
// Edge Detection (dFdx/dFdy)
// Source: OneOffRender Shaders/EdgeDetectionUsing_dFdx_dFdy.glsl (upstream: https://www.shadertoy.com/view/Xtd3W7).
//
// SuperTool intake note: stripped #version, removed OneOffRender Y-flip
// boilerplate (gl_FragCoord is already upright in WebGL2).
// Audio reads remapped iChannel0 → iAudioFFT with Shadertoy↔SuperTool row
// swap (FFT row 0 → 0.75, PCM row 1 → 0.25). Visual logic preserved.

// Original author: gam0022
// Modified by: ArthurTent for ShaderAmp project
// URL: https://www.shadertoy.com/view/Xtd3W7
// License: Creative Commons Attribution-NonCommercial-ShareAlike 3.0 Unported License
// Converted to OneOffRender format

// Audio texture
// Video texture


// copied from QuantumSuper <3
#define getDat(addr) texture(iAudioFFT, vec2(float(addr) / 512.0, 0.75)).x

void main() {
    // Get fragment coordinates with Y-flip for OneOffRender
    vec2 fragCoord = gl_FragCoord.xy;

    vec2 uv = fragCoord / iResolution.xy;
    vec2 uv2 = -1.0 + 2.0 * uv;
    vec4 color = texture(iChannel0, uv);
    float gray = length(color.rgb);
    fragColor = vec4(vec3(step(0.06, length(vec2(dFdx(gray), dFdy(gray))))), 1.0);
    fragColor += vec4(getDat(gray* 5.), getDat(gray* 2.5), getDat(gray*1.05), 0.5);

    // copied from db0x90 "ShitJustGotReal"
    vec3 resultColor = mix(vec3(0.),vec3(fragColor.x, fragColor.y, fragColor.z),pow(max(0.,1.5-length(uv2*uv2*uv2*vec2(2.0,2.0))),.3));
    fragColor = vec4(resultColor, 1.0);
}