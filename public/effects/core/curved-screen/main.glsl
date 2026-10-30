// Curved Screen Squeeze (after Timewarp post.glsl uCurve)
uniform float amount;
uniform float audioPush;
uniform vec3  border;

void mainImage(out vec4 fragColor, in vec2 fragCoord){
  vec2 uv = fragCoord / iResolution.xy;
  float c = amount * (1.0 + audioPush * uAudio);
  float X = (uv.x - 0.5) * 2.0;
  float halfH = 0.5 * (1.0 - c * (0.18 + 0.22 * (1.0 - X * X)));
  float y = (uv.y - 0.5) / (2.0 * halfH) + 0.5;
  float x = 0.5 + (uv.x - 0.5) * (1.0 + c * 0.25 * abs(X));
  // anti-aliased screen edge
  float edge = 1.0 - smoothstep(0.5 - 1.5 / iResolution.y, 0.5, abs(y - 0.5));
  edge *= 1.0 - smoothstep(0.5 - 1.5 / iResolution.x, 0.5, abs(x - 0.5));
  vec3 col = texture(iChannel0, clamp(vec2(x, y), 0.0, 1.0)).rgb;
  fragColor = vec4(mix(border, col, edge), 1.0);
}
