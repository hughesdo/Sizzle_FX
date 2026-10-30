// Imported from SuperTool psychedelic-trails/buffer_b.glsl
// ============================================
// BUFFER B - Psychedelic Tracer Effect (AUDIO REACTIVE)
// ============================================

#version 330 core

uniform sampler2D iChannel0;  // Self-feedback (BufferB previous frame)
uniform sampler2D iChannel1;  // Video input (BufferA)
uniform vec3 iResolution;
uniform float iTime;

// Audio data (bass, mid, high) — use standard preamble names



// Tweakable parameters
uniform float trailLength;      // 0.0 = no trails, 0.99 = very long trails
uniform float colorSpeed;       // How fast colors cycle
uniform float colorSpread;      // How much color varies by position
uniform float effectIntensity;  // Brightness of new tracer pixels
uniform float saturation;       // Color saturation

// Audio reactivity strengths
uniform float bassBrightness;   // How much bass boosts brightness
uniform float bassHueShift;     // How much bass shifts colors
uniform float highSaturation;   // How much highs boost saturation

in vec2 fragCoord;
out vec4 fragColor;

vec3 hsv2rgb(vec3 c) {
    vec4 K = vec4(1.0, 2.0/3.0, 1.0/3.0, 3.0);
    vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

void main()
{
    vec2 px = 1.5 / iResolution.xy;
    vec2 uv = fragCoord / iResolution.xy;

    // ===== AUDIO REACTIVITY =====
    float bass = audioBand(20.0, 250.0);
    float mid = audioBand(250.0, 4000.0);
    float high = audioBand(4000.0, 16000.0);

    // ===== EDGE DETECTION =====
    vec4 tx = texture(iChannel1, uv);
    float dist = distance(tx, texture(iChannel1, uv + px));
    px.y *= -1.0;
    dist += distance(tx, texture(iChannel1, uv + px));
    px.x *= -1.0;
    dist += distance(tx, texture(iChannel1, uv + px));
    px.y *= -1.0;
    dist += distance(tx, texture(iChannel1, uv + px));

    // ===== TRANSFORM =====
    uv *= mat2(0.99, 0.01, -0.001, 0.99);

    // ===== FEEDBACK WITH DECAY =====
    vec4 feedback = texture(iChannel0, uv + 0.002);
    feedback.rgb *= trailLength;

    // ===== PSYCHEDELIC COLORS =====
    float time = iTime;

    // Rainbow hue cycling
    float hue = fract(time * colorSpeed + uv.y * colorSpread + bass * bassHueShift);

    // Intensity from edge detection
    float intensity = smoothstep(0.3, 0.8, dist) + smoothstep(0.3, 1.4, dist);

    // Audio modulates brightness
    float val = intensity * (1.0 + bass * bassBrightness);

    // Saturation with audio boost
    float sat = saturation + high * highSaturation;

    vec3 trippyColor = hsv2rgb(vec3(hue, sat, val));

    // ===== COMBINE =====
    vec3 result = feedback.rgb + trippyColor * effectIntensity;
    result = clamp(result, 0.0, 1.0);

    fragColor = vec4(result, 1.0);
}
