// Background Swap: new background, subject composited back over it by the matte.
uniform int   mode;
uniform float blur;
uniform vec3  colorA;
uniform vec3  colorB;
uniform float hueShift;
uniform float audioPush;

vec3 rotHue(vec3 c, float a){ const vec3 k = vec3(0.57735); float ca = cos(a); return c * ca + cross(k, c) * sin(a) + k * dot(k, c) * (1.0 - ca); }

void mainImage(out vec4 fragColor, in vec2 fragCoord){
  vec2 uv = fragCoord / iResolution.xy;
  vec3 base = texture(iChannel0, uv).rgb;
  float m0 = maskAt(uv);
  float pulse = 1.0 + audioPush * uAudio;
  vec3 bg;
  if (mode == 0){
    // blur that ignores the subject so it doesn't bleed a halo into the background
    vec2 r = blur * (iResolution.y / 1080.0) / iResolution.xy;
    vec3 acc = vec3(0.0); float ws = 0.0;
    for (int i = 0; i < 48; i++){
      float fi = float(i) + 0.5;
      vec2 o = vec2(cos(fi * 2.39996), sin(fi * 2.39996)) * sqrt(fi / 48.0) * r;
      float w = 1.0 - maskAt(uv + o) * 0.95;
      acc += texture(iChannel0, uv + o).rgb * w; ws += w;
    }
    bg = acc / max(ws, 1e-3);
  } else if (mode == 1) bg = colorA;
  else if (mode == 2) bg = mix(colorB, colorA, smoothstep(0.0, 1.0, uv.y + 0.15 * sin(iTime * 0.5 + uv.x * 2.0)));
  else if (mode == 3) bg = vec3(0.0);
  else bg = rotHue(base, hueShift * 6.2832);
  bg *= pulse;
  fragColor = vec4(mix(bg, base, m0), 1.0);
}
