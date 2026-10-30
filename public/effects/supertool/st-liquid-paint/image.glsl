// Imported from SuperTool liquid-paint/image.glsl
// ============================================
// IMAGE - Final Composite / Polish
// Saturation + contrast lift on the paint, with an optional crisp-video
// overlay so you can dial back toward the recognizable clip.
// ============================================

#version 330 core

uniform sampler2D iChannel0;  // Buffer A (clean video)
uniform sampler2D iChannel1;  // Buffer B (liquid paint)
uniform vec3 iResolution;
uniform float iTime;

uniform float saturation;  // Paint saturation lift
uniform float contrast;    // Paint contrast lift
uniform float videoMix;    // Blend crisp video back over the paint (0 = pure paint)

in vec2 fragCoord;
out vec4 fragColor;

vec3 rgb2hsv(vec3 c) {
    vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
    vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
    vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
    float d = q.x - min(q.w, q.y);
    float e = 1.0e-10;
    return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 hsv2rgb(vec3 c) {
    vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

void main()
{
    vec2 uv = fragCoord / iResolution.xy;

    vec3 paint = texture(iChannel1, uv).rgb;
    vec3 video = texture(iChannel0, uv).rgb;
    vec3 col = mix(paint, video, clamp(videoMix, 0.0, 1.0));

    vec3 h = rgb2hsv(col);
    h.y = clamp(h.y * saturation, 0.0, 1.0);
    col = hsv2rgb(h);

    col = clamp((col - 0.5) * contrast + 0.5, 0.0, 1.0);

    fragColor = vec4(col, 1.0);
}
