// Imported from SuperTool effects/AfterEffectsTikTokEdit.glsl by scripts/import-supertool.mjs
// After Effects TikTok Edit
// Chaotic tan()-driven UV warp + ray-zoom + flicker + vignette + desaturation.
// Ported from DISCO-GLSL-Video-Processor (Shaders/After EffectsTik Tok Edit.glsl).
//
// The DISCO original declared uniforms but ignored them — every visual
// constant was hardcoded inline as "baseline behavior". This port keeps the
// same look at default values, exposes them as real uniforms so the effect
// can actually be tuned, and offers OPT-IN bass/RMS reactivity (boost knobs
// default to 0 — the look is purely time-driven like the DISCO original).

uniform float intensity;          // 0 = passthrough, 1 = full effect
uniform float shakeAmount;        // chaotic UV-warp strength multiplier
uniform float audioShakeBoost;    // extra shake at peak audio (0 = off)
uniform float flickerAmount;      // brightness flicker amplitude
uniform float flickerSpeed;       // flicker rate (radians/sec)
uniform float vignetteAmount;     // 0 = none, 1 = full corner darkening
uniform float rayDecay;           // per-iteration UV scale step (orig: 0.0002)
uniform float maxRaySamples;      // hard ceiling on ray loop iterations
uniform float audioRayBoost;      // extra ray count fraction at peak audio (0 = off)
uniform float saturation;         // DISCO desat-matrix param (orig: 0.3)

#define PI 3.1415926538

float decreaseLightTransition(float adjustedLighting, float originalLighting, float speed) {
    return pow(4.0, smoothstep(adjustedLighting, originalLighting, sin(iTime * speed)));
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;
    vec2 origUv = uv;

    // Audio drive — bass and RMS jointly modulate shake and ray count.
    float audioEnergy = max(audioBand(20.0, 250.0), audioRMS());
    float shakeMul    = shakeAmount * (1.0 + audioShakeBoost * audioEnergy);

    // Restore the DISCO-original chaotic UV warp. The local `progress` in
    // the original shadowed the uniform of the same name, so we keep it
    // local-only here too.
    float progress = 500.0 * tan(iTime * 4.245) / iResolution.x - 1.0;

    vec2 editUV = 0.4 + (uv.y + tan(iTime * atan(iTime * 8.0)))
                * sin(uv.x / max(uv.x, 0.001) - 0.32 + tan(sin(iTime * 0.1 * tan(iTime))))
                * vec2((uv * 2.0) - 1.0);

    // Note: the DISCO original computed a `shake` vector but never actually
    // sampled with it — the displacement below is the only one applied.
    vec2 displacement = editUV * (atan(progress * PI / 50.0) / sin(iTime + 0.1)) * shakeMul;

    // Sample the warped video.
    vec4 col = texture(iChannel0, displacement + uv);

    // Brightness flicker — DISCO original was `0.99 + 0.1 * sin(110*t)` exactly.
    // Keep the 0.99 baseline (a deliberate ~1% darken that's part of the look)
    // and let flickerAmount scale the sine component.
    col *= 0.99 + flickerAmount * sin(flickerSpeed * iTime);

    // Vignette — fade between flat (1.0) and the original corner-darken term.
    float vig = 0.5 + 0.5 * 16.0 * uv.x * uv.y * (1.0 - uv.x) * (1.0 - uv.y);
    col *= mix(1.0, vig, vignetteAmount);

    // Periodic darken/brighten swing (DecreaseLightTransition) — kept verbatim.
    col *= decreaseLightTransition(12.0, 0.0, 2.0);

    // Ray-zoom accumulator. The original used `140 * fract(215 - tan(t)*1.28)`
    // which oscillates 0..140 over time — that's preserved as the upper
    // envelope, then audio adds boost and the user uniform caps the worst
    // case so a single shader can't tank the GPU.
    float baseRayCount = 140.0 * fract(215.0 - tan(iTime) * 1.28);
    float rayCount = baseRayCount * (1.0 + audioRayBoost * audioEnergy);
    rayCount = clamp(rayCount, 0.0, maxRaySamples);

    float rayScale = 1.0;
    vec2 rayUv = uv;
    for (float i = 0.0; i < rayCount; i++) {
        rayScale -= rayDecay;
        rayUv -= abs(cos(iTime));
        rayUv *= rayScale;
        rayUv += abs(cos(iTime));
        col += smoothstep(0.0, 0.8, texture(iChannel0, displacement + rayUv) * 0.2);
    }

    // Saturation matrix — replicated from the DISCO original verbatim so that
    // saturation=0.3 reproduces the exact "bleached/darkened" look. The math
    // isn't a true saturation control: at s=0.3 the diagonal works out to
    // ~0.292 and off-diagonals to ~-0.008, i.e. col is mostly *darkened*
    // ~3.4× with a very small channel cross-bleed. Calling it `saturation`
    // matches the DISCO uniform name even though the effect is closer to a
    // weighted brightness scale.
    {
        vec3 luminance = vec3(0.04, 0.04, 0.04);
        float oneMinusSat = 0.1 - saturation;
        vec3 red   = vec3(luminance.x * oneMinusSat) + vec3(saturation, 0.0, 0.0);
        vec3 green = vec3(luminance.y * oneMinusSat) + vec3(0.0, saturation, 0.0);
        vec3 blue  = vec3(luminance.z * oneMinusSat) + vec3(0.0, 0.0, saturation);
        mat4 fullSat = mat4(
            vec4(red,   0.0),
            vec4(green, 0.0),
            vec4(blue,  0.0),
            vec4(0.0, 0.0, 0.0, 1.0)
        );
        col = col * fullSat;
    }

    // Final blend — let users dial the whole thing in/out against the source.
    vec3 source = texture(iChannel0, origUv).rgb;
    col.rgb = mix(source, col.rgb, intensity);

    fragColor = vec4(col.rgb, 1.0);
}
