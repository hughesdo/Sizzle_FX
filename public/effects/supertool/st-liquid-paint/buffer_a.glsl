// Imported from SuperTool liquid-paint/buffer_a.glsl
// ============================================
// BUFFER A - Video Input Pass-through
// Hands the live clip frame to the fluid sim (Buffer B) as a clean texture.
// ============================================

#version 330 core

uniform sampler2D iChannel0;  // Input video (the timeline layer below)
uniform vec3 iResolution;
uniform float iTime;

in vec2 fragCoord;
out vec4 fragColor;

void main()
{
    vec2 uv = fragCoord / iResolution.xy;
    fragColor = texture(iChannel0, uv);
}
