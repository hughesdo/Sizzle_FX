// Neon Outline: mask edge (dilate - erode on a ring) + soft outer glow.
uniform float width;
uniform float glow;
uniform vec3  color;
uniform float rainbow;
uniform float intensity;
uniform float darkenBg;
uniform float audioPush;

vec3 hue(float h){ return clamp(abs(fract(h + vec3(0.0, 2.0, 1.0) / 3.0) * 6.0 - 3.0) - 1.0, 0.0, 1.0); }

void mainImage(out vec4 fragColor, in vec2 fragCoord){
  vec2 uv = fragCoord / iResolution.xy;
  vec3 base = texture(iChannel0, uv).rgb;
  float s = iResolution.y / 1080.0;
  float pump = 1.0 + audioPush * uAudio;
  vec2 px = 1.0 / iResolution.xy;
  float m0 = maskAt(uv);
  // edge: max/min of the mask on a small ring
  float mx = m0, mn = m0;
  float r = width * s * 0.5 * pump;
  for (int i = 0; i < 12; i++){
    float a = float(i) * 0.5236;
    float v = maskAt(uv + vec2(cos(a), sin(a)) * r * px);
    mx = max(mx, v); mn = min(mn, v);
  }
  float edge = smoothstep(0.25, 0.75, mx) * (1.0 - smoothstep(0.25, 0.75, mn));
  // glow: blurred mask outside the subject
  float g = 0.0; float gr = glow * s * pump;
  for (int i = 0; i < 24; i++){
    float fi = float(i) + 0.5;
    float d = sqrt(fi / 24.0) * gr;
    float a = fi * 2.39996;
    g += maskAt(uv + vec2(cos(a), sin(a)) * d * px);
  }
  g = g / 24.0 * (1.0 - m0);
  vec3 c = rainbow > 0.5 ? hue(atan(uv.y - uMaskCentroid.y, uv.x - uMaskCentroid.x) / 6.2832 + iTime * 0.2) : color;
  vec3 col = base * (1.0 - darkenBg * (1.0 - m0));
  col += c * (edge * 1.5 + g * 0.9) * intensity * pump;
  fragColor = vec4(col, 1.0);
}
