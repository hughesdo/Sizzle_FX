// Imported from SuperTool effects/Surf3.glsl by scripts/import-supertool.mjs
/*
    "Surf 3" - Audio-Reactive Version with Video Keying by Augment Agent
    Based on "Surf 2" by @XorDev

    Original discovery: interesting refraction effect by adding
    the raymarch iterator to the turbulence!
    https://x.com/XorDev/status/1936174781352517638

    Special feature: Video keying - input video shows through on black areas
*/

// SuperTool intake note: ported from DISCO-GLSL-Video-Processor (Shaders/Surf3.glsl).
// #version / standard uniform / in-out decls dropped (GLSLRenderer injects them).
// iChannel0 = the layer-below video (keyed through its dark areas). DISCO's host
// midLevel uniform is mapped to audioBand(250,4000). The raymarch coordinate I
// reproduces DISCO's v_text*iResolution.xy (y-down) via a Y-flip; the video keys at
// the SuperTool-upright fragCoord/res. XorDev's golf loop left z/i uninitialized;
// they are explicitly 0-initialized here (WebGL2 doesn't guarantee zero-init and
// the 100-step loop count depends on i starting at 0).

void mainImage(out vec4 fragColor, in vec2 fragCoord)
{
    vec2 I = vec2(fragCoord.x, iResolution.y - fragCoord.y);

    float midLevel = audioBand(250.0, 4000.0);

    //Raymarch depth / step distance / iterator / time
    float z = 0.0, d, i = 0.0, t = iTime;

    vec4 O = vec4(0.0);

    for (O *= i; i++ < 1e2;
        O += (1.0 + cos(i*0.7 + vec4(6, 1, 2, 0))) / d / i)
    {
        //Sample point (from ray direction)
        vec3 p = z*normalize(vec3(I+I, 0) - iResolution.xyx);

        //Polar coordinates
        p = vec3(atan(p.y, p.x)*2.0, p.z/3.0, length(p.xy) - 6.0);

        //Apply turbulence with gentle mid-frequency variation
        //https://mini.gmshaders.com/p/turbulence
        for (d = 1.0; d < 9.0;)
        {
            float turbulenceAmount = 1.0 + midLevel * 0.15;
            p += sin(p.yzx*d - t + 0.2*i) * turbulenceAmount / d++;
        }

        //Distance to cylinder and waves
        z += d = 0.2*length(vec4(p.z, 0.1*cos(p*3.0) - 0.1));
    }

    //Tanh tonemap
    O = tanh(O*O / 9e2);

    // Video keying - show surf through black areas of input video (upright sample)
    vec3 videoColor = texture(iChannel0, fragCoord / iResolution.xy).rgb;
    float videoLuminance = dot(videoColor, vec3(0.299, 0.587, 0.114));
    float keyThreshold = 0.1;
    float keyMix = smoothstep(0.0, keyThreshold, videoLuminance);

    vec3 finalColor = mix(O.rgb, videoColor, keyMix);

    fragColor = vec4(finalColor, 1.0);
}
