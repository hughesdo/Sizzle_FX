// Kick Zoom + Shake
uniform float zoom;
uniform float shake;
uniform float rotate;
uniform float baseZoom;

float hash11(float p){ p = fract(p * 0.1031); p *= p + 33.33; p *= p + p; return fract(p); }

void mainImage(out vec4 fragColor, in vec2 fragCoord){
  vec2 uv = fragCoord / iResolution.xy;
  float aspect = iResolution.x / iResolution.y;
  float k = uAudio;
  float tick = floor(iTime * 24.0) + uSeed;
  vec2 jolt = (vec2(hash11(tick), hash11(tick + 7.1)) - 0.5) * 2.0 * shake * k;
  float r = (hash11(tick + 3.3) - 0.5) * 2.0 * rotate * k;
  vec2 p = (uv - 0.5) * vec2(aspect, 1.0);
  p = mat2(cos(r), -sin(r), sin(r), cos(r)) * p;
  p /= 1.0 + baseZoom + zoom * k;
  vec2 u = p / vec2(aspect, 1.0) + 0.5 + jolt;
  // mirror at the borders instead of smearing the edge pixels
  u = 1.0 - abs(1.0 - abs(u));
  fragColor = vec4(texture(iChannel0, u).rgb, 1.0);
}
