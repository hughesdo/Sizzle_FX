// Edge Neon (after Timewarp post.glsl edge pass)
uniform float strength;
uniform float keep;
uniform float audioPush;
uniform float width;
uniform vec3  tint;

float lum(vec2 u){ return dot(texture(iChannel0, u).rgb, vec3(0.299, 0.587, 0.114)); }

void mainImage(out vec4 fragColor, in vec2 fragCoord){
  vec2 uv = fragCoord / iResolution.xy;
  vec2 px = width / iResolution.xy;
  float gx = lum(uv + vec2(px.x, 0)) - lum(uv - vec2(px.x, 0));
  float gy = lum(uv + vec2(0, px.y)) - lum(uv - vec2(0, px.y));
  float e = clamp(length(vec2(gx, gy)) * strength, 0.0, 1.0);
  vec3 col = texture(iChannel0, uv).rgb;
  vec3 hue = normalize(col + 0.05) * 1.4 * tint;
  float glow = 1.6 * (1.0 + audioPush * uAudio);
  fragColor = vec4(hue * e * glow + col * keep, 1.0);
}
