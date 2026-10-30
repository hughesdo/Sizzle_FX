// Imported from SuperTool effects/LiquidSplash.glsl by scripts/import-supertool.mjs
// Liquid Splash
// Organic FBM splash blobs with rippling and edge highlights, colored and
// thresholded by bass/mid/high audio; blended over the video.
// Ported from DISCO-GLSL-Video-Processor (Shaders/LiquidSplash.glsl)
// DISCO sampled an audio texture; here bass/mid/high come from the FFT bands.

uniform float splashScale;
uniform float splashSpeed;
uniform float splashThreshold;
uniform float bassThreshold;
uniform float rippleFrequency;
uniform float rippleSpeed;
uniform float splashIntensity;
uniform float edgeIntensity;
uniform float blendAmount;

float hash21(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = hash21(i);
    float b = hash21(i + vec2(1.0, 0.0));
    float c = hash21(i + vec2(0.0, 1.0));
    float d = hash21(i + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
    float value = 0.0;
    float amplitude = 0.5;
    float frequency = 1.0;
    for (int i = 0; i < 5; i++) {
        value += amplitude * noise(p * frequency);
        frequency *= 2.0;
        amplitude *= 0.5;
    }
    return value;
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;

    vec3 videoCol = texture(iChannel0, uv).rgb;

    float bass = audioBand(20.0, 250.0);
    float mid = audioBand(250.0, 4000.0);
    float high = audioBand(4000.0, 16000.0);

    vec2 splashUv = uv * splashScale;
    splashUv.x += iTime * splashSpeed * 0.1;

    float splash1 = fbm(splashUv + vec2(iTime * splashSpeed * 0.2, 0.0));
    float splash2 = fbm(splashUv * 1.5 - vec2(0.0, iTime * splashSpeed * 0.3));
    float splash3 = fbm(splashUv * 2.0 + vec2(iTime * splashSpeed * 0.15, -iTime * splashSpeed * 0.15));

    float splashMask = splash1 * splash2 * splash3;
    splashMask = smoothstep(splashThreshold - bass * bassThreshold, 0.7, splashMask);

    float intensity = bass * 0.5 + mid * 0.3 + high * 0.2;

    vec3 splashColor = vec3(
        0.3 + bass,
        0.5 + mid,
        0.8 + high
    );

    vec2 center = vec2(0.5);
    float dist = length(uv - center);
    float ripple = sin(dist * rippleFrequency - iTime * rippleSpeed) * 0.5 + 0.5;
    ripple *= intensity;

    splashMask = max(splashMask, ripple * 0.3);

    vec2 gradUv = splashUv + vec2(0.01);
    float splash1_grad = fbm(gradUv + vec2(iTime * splashSpeed * 0.2, 0.0));
    float splash2_grad = fbm(gradUv * 1.5 - vec2(0.0, iTime * splashSpeed * 0.3));
    float splash3_grad = fbm(gradUv * 2.0 + vec2(iTime * splashSpeed * 0.15, -iTime * splashSpeed * 0.15));
    float splashMask_grad = smoothstep(splashThreshold - bass * bassThreshold, 0.7, splash1_grad * splash2_grad * splash3_grad);

    float edge = abs(splashMask - splashMask_grad) * 5.0;
    edge = smoothstep(0.5, 1.0, edge);

    vec3 edgeColor = splashColor * edgeIntensity;

    vec3 finalSplash = splashColor * splashMask * splashIntensity + edgeColor * edge;

    float alpha = (splashMask + edge) * intensity * blendAmount;

    vec3 col = mix(videoCol, finalSplash, alpha);

    fragColor = vec4(col, 1.0);
}
