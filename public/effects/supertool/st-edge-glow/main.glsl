// Imported from SuperTool effects/EdgeGlow.glsl by scripts/import-supertool.mjs
// Edge Glow Effect
// Sobel edge detection with colorful audio-reactive glow
// Bass = red, mid = green, high = blue glow on edges
// Ported from DISCO-GLSL-Video-Processor (Effects/EdgeGlow.glsl)

uniform float edgeThresholdLow;
uniform float edgeThresholdHigh;
uniform float glowIntensity;
uniform float blurKernelBase;
uniform float blurKernelAudio;
uniform float bassColorMult;
uniform float midColorMult;
uniform float highColorMult;
uniform float pulseMult;

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;
    vec2 pixel = 1.0 / iResolution.xy;

    // Audio from FFT + standard uniforms
    float audio = max(texture(iAudioFFT, vec2(0.1, 0.25)).x, audioRMS());
    float bass = max(texture(iAudioFFT, vec2(0.05, 0.25)).x, audioBand(20.0, 250.0));
    float mid = max(texture(iAudioFFT, vec2(0.2, 0.25)).x, audioBand(250.0, 4000.0));
    float high = max(texture(iAudioFFT, vec2(0.4, 0.25)).x, audioBand(4000.0, 16000.0));

    // Sobel edge detection
    vec3 c = texture(iChannel0, uv).rgb;

    vec3 tl = texture(iChannel0, uv + vec2(-pixel.x, pixel.y)).rgb;
    vec3 t  = texture(iChannel0, uv + vec2(0.0, pixel.y)).rgb;
    vec3 tr = texture(iChannel0, uv + vec2(pixel.x, pixel.y)).rgb;
    vec3 l  = texture(iChannel0, uv + vec2(-pixel.x, 0.0)).rgb;
    vec3 r  = texture(iChannel0, uv + vec2(pixel.x, 0.0)).rgb;
    vec3 bl = texture(iChannel0, uv + vec2(-pixel.x, -pixel.y)).rgb;
    vec3 b  = texture(iChannel0, uv + vec2(0.0, -pixel.y)).rgb;
    vec3 br = texture(iChannel0, uv + vec2(pixel.x, -pixel.y)).rgb;

    vec3 sobelX = -tl - 2.0*l - bl + tr + 2.0*r + br;
    vec3 sobelY = -tl - 2.0*t - tr + bl + 2.0*b + br;

    float edgeX = length(sobelX);
    float edgeY = length(sobelY);
    float edge = sqrt(edgeX * edgeX + edgeY * edgeY);
    edge = smoothstep(edgeThresholdLow, edgeThresholdHigh, edge);

    // Audio-reactive glow color
    vec3 glowColor = vec3(
        bass * bassColorMult,
        mid * midColorMult,
        high * highColorMult
    );

    // Pulsing glow
    float pulse = 1.0 + audio * pulseMult;

    // Apply glow to edges
    vec3 glow = edge * glowColor * pulse * glowIntensity;

    // Soft blur pass for glow spread
    vec3 blurredGlow = vec3(0.0);
    float kernelSize = blurKernelBase + audio * blurKernelAudio;
    float samples = 0.0;

    for (float x = -2.0; x <= 2.0; x += 1.0) {
        for (float y = -2.0; y <= 2.0; y += 1.0) {
            vec2 offset = vec2(x, y) * pixel * kernelSize;
            vec3 offsetC = texture(iChannel0, uv + offset).rgb;
            vec3 offsetTL = texture(iChannel0, uv + offset + vec2(-pixel.x, pixel.y)).rgb;
            vec3 offsetBR = texture(iChannel0, uv + offset + vec2(pixel.x, -pixel.y)).rgb;

            float offsetEdge = length(offsetTL - offsetBR);
            offsetEdge = smoothstep(edgeThresholdLow, edgeThresholdHigh, offsetEdge);

            blurredGlow += offsetEdge * glowColor;
            samples += 1.0;
        }
    }

    blurredGlow /= samples;
    blurredGlow *= pulse * 0.5;

    // Combine original video with glow
    vec3 finalColor = c + glow + blurredGlow;

    fragColor = vec4(finalColor, 1.0);
}
