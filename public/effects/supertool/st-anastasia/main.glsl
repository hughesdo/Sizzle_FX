// Imported from SuperTool effects/Anastasia.glsl by scripts/import-supertool.mjs
// Anastasia
// Source: OneOffRender Shaders/Anastasia.glsl (upstream: https://www.shadertoy.com/view/4dcSRj).
//
// SuperTool intake note: stripped #version, removed OneOffRender Y-flip
// boilerplate (gl_FragCoord is already upright in WebGL2).
// Audio reads remapped iChannel0 → iAudioFFT with Shadertoy↔SuperTool row
// swap (FFT row 0 → 0.75, PCM row 1 → 0.25). Visual logic preserved.

// Original author: s23b
// Modified by: ArthurTent for ShaderAmp project
// URL: https://www.shadertoy.com/view/4dcSRj
// License: Creative Commons Attribution-NonCommercial-ShareAlike 3.0 Unported License
// Converted to OneOffRender format

// https://www.shadertoy.com/view/4dcSRj
// Modified by ArthurTent
// Created by s23b
// License: Creative Commons Attribution-NonCommercial-ShareAlike 3.0 Unported License.
// https://creativecommons.org/licenses/by-nc-sa/3.0/

// Audio texture
// Video texture


void main( )
{
	//vec2 uv = fragCoord.xy / iResolution.xy * 2. - 1.;
	vec2 uv = -1.0 + 2.0* gl_FragCoord.xy / iResolution.xy;
    uv.x *= iResolution.x / iResolution.y;

    // mirror everything across x and y axex
    uv = abs(uv);

    // init to black
    fragColor = vec4(vec3(0), 1);

    // add horizontal and vertical scrolling sine waves
    fragColor.rgb += smoothstep(.2, .24, sin(uv.x + iTime * vec3(1, 2, 4)) + .5 - uv.y);
    fragColor.rgb += smoothstep(.2, .24, sin(uv.y * 2. + iTime * vec3(1, 2, 4)) / 2. + 1. - uv.x);

    // flip colors that are out of bounds
    fragColor.rgb = abs(1. - fragColor.rgb);

    // rotate space around the center
    float angel = iTime * .2,
        s = sin(angel),
        c = cos(angel);
    uv *= mat2(c, -s, s, c);

    // multiply by video texture
    fragColor *= texture(iChannel0, abs(.5 - fract(uv)) * 2.);

    // offset space according to spikes in fft data
    uv *= 10. + texture(iAudioFFT, vec2(.3, 0.75)).x * 5.;

    // add morphing sine grid
    fragColor *= clamp(sin(uv.x) * sin(uv.y) * 20. + sin(iTime) * 5., 0., 1.) + .5;

}