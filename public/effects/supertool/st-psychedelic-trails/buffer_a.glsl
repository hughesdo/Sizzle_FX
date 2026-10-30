// Imported from SuperTool psychedelic-trails/buffer_a.glsl
// ============================================
// BUFFER A - Video Input Pass-through
// ============================================

#version 330 core

uniform sampler2D iChannel0;  // Input video
uniform vec3 iResolution;
uniform float iTime;

in vec2 fragCoord;
out vec4 fragColor;

void main()
{
    vec2 uv = fragCoord / iResolution.xy;
    fragColor = texture(iChannel0, uv);
}
