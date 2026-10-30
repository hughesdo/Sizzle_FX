// Imported from SuperTool effects/EnergyTunnel.glsl by scripts/import-supertool.mjs
// Energy Tunnel
// Rushing polar tunnel of rings and rotating segments with audio-reactive
// color (bass=red, mid=green, general=blue) and a bass-driven pulse.
// Ported from DISCO-GLSL-Video-Processor (Shaders/EnergyTunnel.glsl)
// DISCO sampled an audio texture; here bass/mid/general come from the FFT bands.

uniform float tunnelSpeed;
uniform float bassTunnelSpeed;
uniform float ringSharpness;
uniform float segmentCount;
uniform float segmentSpeed;
uniform float pulseSpeed;
uniform float bassPulse;
uniform float tunnelIntensity;
uniform float centerFade;
uniform float blendAmount;

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;

    vec3 videoCol = texture(iChannel0, uv).rgb;

    float bass = audioBand(20.0, 250.0);
    float mid = audioBand(250.0, 4000.0);
    float audio = audioRMS();

    vec2 center = vec2(0.5);
    vec2 delta = uv - center;

    float radius = length(delta);
    float angle = atan(delta.y, delta.x);

    float depth = 1.0 / (radius + 0.1);
    float tunnel = depth + iTime * (tunnelSpeed + bass * bassTunnelSpeed);

    float rings = fract(tunnel);
    rings = smoothstep(0.3, 0.5, rings) - smoothstep(0.5, 0.7, rings);
    rings = pow(rings, ringSharpness);

    float segmentPattern = sin(angle * segmentCount + iTime * segmentSpeed);
    segmentPattern = smoothstep(0.0, 0.3, segmentPattern);

    float pattern = rings * segmentPattern;

    float pulse = 0.5 + 0.5 * sin(iTime * pulseSpeed + bass * bassPulse);

    vec3 tunnelColor = vec3(
        0.2 + bass * 0.8,
        0.5 + mid * 0.5,
        0.8 + audio * 0.2
    );

    vec3 energy = pattern * tunnelColor * tunnelIntensity * (1.0 + pulse * bass * 2.0);

    float fade = 1.0 - smoothstep(0.0, centerFade, radius);
    energy *= fade;

    vec3 col = videoCol + energy * blendAmount;

    fragColor = vec4(col, 1.0);
}
