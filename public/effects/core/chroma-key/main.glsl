// Chroma Key: YCbCr chroma distance (same metric as the "green screen" mask bake) + despill.
uniform vec3  keyColor;
uniform float tolerance;
uniform float softness;
uniform float spill;
uniform int   background;
uniform vec3  colorA;
uniform vec3  colorB;
uniform float audioPush;

vec2 cbcr(vec3 c){ return vec2(-0.168736 * c.r - 0.331264 * c.g + 0.5 * c.b, 0.5 * c.r - 0.418688 * c.g - 0.081312 * c.b); }
float alphaAt(vec2 u, vec2 key){
  float d = distance(cbcr(texture(iChannel0, u).rgb), key) / 0.706; // 0..~1
  return clamp((d - tolerance) / softness, 0.0, 1.0);
}

void mainImage(out vec4 fragColor, in vec2 fragCoord){
  vec2 uv = fragCoord / iResolution.xy;
  vec3 c = texture(iChannel0, uv).rgb;
  vec2 key = cbcr(keyColor);
  float a = alphaAt(uv, key);
  // despill: pull the key's dominant channel down to the other two
  vec3 k = normalize(keyColor + 1e-4);
  vec3 dc = c;
  if (k.g >= k.b && k.g >= k.r) dc.g = mix(c.g, min(c.g, max(c.r, c.b)), spill);
  else if (k.b >= k.r) dc.b = mix(c.b, min(c.b, max(c.r, c.g)), spill);
  else dc.r = mix(c.r, min(c.r, max(c.g, c.b)), spill);
  if (background == 4){ fragColor = vec4(dc, 1.0); return; }
  vec3 bg;
  if (background == 0) bg = colorA;
  else if (background == 1) bg = mix(colorB, colorA, smoothstep(0.0, 1.0, uv.y + 0.1 * sin(iTime * 0.6 + uv.x * 3.0)));
  else if (background == 2){
    vec3 acc = vec3(0.0); float ws = 0.0;
    vec2 r = 28.0 * (iResolution.y / 1080.0) / iResolution.xy;
    for (int i = 0; i < 32; i++){
      float fi = float(i) + 0.5;
      vec2 o = vec2(cos(fi * 2.39996), sin(fi * 2.39996)) * sqrt(fi / 32.0) * r;
      vec3 s = texture(iChannel0, uv + o).rgb;
      float w = 1.0 - alphaAt(uv + o, key) * 0.95;      // don't smear the subject into the plate
      acc += s * w; ws += w;
    }
    bg = acc / max(ws, 1e-3);
    bg = mix(bg, vec3(dot(bg, vec3(0.333))), 0.6) * 0.6;   // tame the green plate
  } else bg = vec3(0.0);
  bg *= 1.0 + audioPush * uAudio;
  fragColor = vec4(mix(bg, dc, a), 1.0);
}
