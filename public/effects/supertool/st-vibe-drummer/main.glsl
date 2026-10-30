// Imported from SuperTool effects/VibeDrummer1.glsl by scripts/import-supertool.mjs
// Vibe Drummer 1
// Beat-reactive psychedelic distance-field recoloring of the video; bass/kick
// detection drives extra movement and a beat flash.
// Ported from DISCO-GLSL-Video-Processor (Shaders/VibeDrummer1.glsl)
// DISCO summed low FFT bins for bass; here it comes from audioBand(20,200).

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;
    vec3 inColor = texture(iChannel0, uv).xyz;

    float bassLevel = audioBand(20.0, 200.0);

    float beatThreshold = 0.15;
    float beatIntensity = smoothstep(beatThreshold, beatThreshold + 0.1, bassLevel);

    float beatPulse = beatIntensity * (1.0 + sin(iTime * 20.0) * 0.5);

    float baseTime = iTime * 0.3;
    float beatTime = iTime * beatPulse;
    float animTime = baseTime + beatTime;

    uv.x *= iResolution.x / iResolution.y;

    float scaleMultiplier = 20.0 + (5.0 * beatIntensity);
    uv *= scaleMultiplier;

    float r = distance(uv * sin(animTime * 0.2), inColor.xy * vec2(sin(animTime * 2.0), sin(animTime) * 0.1));
    float g = distance(-uv, inColor.xz * vec2(inColor.x, inColor.y));
    float b = distance(uv, inColor.zy * vec2(r, sin(animTime)));

    float value = abs(sin(r + animTime) + sin(g + animTime) + sin(b + animTime) + sin(uv.x + animTime) + cos(uv.y + animTime));
    value *= 64.0 * (1.0 + beatIntensity);

    r /= value;
    g /= value / (sin(animTime) * 0.5 + 0.5);
    b /= value;

    vec3 beatColor = vec3(beatIntensity * 0.2);
    vec3 rgb = vec3(r, g, b) + (inColor / 15.0) + beatColor;

    fragColor = vec4(rgb, 1.0);
}
