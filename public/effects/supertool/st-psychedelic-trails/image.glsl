// Imported from SuperTool psychedelic-trails/image.glsl
// ============================================
// IMAGE - Final Composite Output
// ============================================

#version 330 core

uniform sampler2D iChannel0;  // Buffer A (original video)
uniform sampler2D iChannel1;  // Buffer B (psychedelic tracer effect)
uniform vec3 iResolution;
uniform float iTime;

in vec2 fragCoord;
out vec4 fragColor;

void main()
{
    vec2 uv = fragCoord / iResolution.xy;
    fragColor = max(texture(iChannel0, uv), texture(iChannel1, uv + 0.002));
}
