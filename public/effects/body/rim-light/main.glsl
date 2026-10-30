// Rim Light: for each subject pixel, how quickly the matte ends toward the light direction
// (inside edge = lit). Key light from `angle`, a back light from the opposite side.
uniform float angle;
uniform float spin;
uniform float width;
uniform vec3  colorA;
uniform vec3  colorB;
uniform float intensity;
uniform float bloom;
uniform float audioPush;

// fraction of samples along `dir` (in px) that leave the matte: 1 at the lit edge, 0 deep inside
float rimToward(vec2 uv, vec2 dir, float W){
  vec2 px = 1.0 / iResolution.xy;
  float acc = 0.0, wsum = 0.0;
  for (int i = 1; i <= 8; i++){
    float t = float(i) / 8.0;
    float w = 1.0 - t * 0.6;
    acc += (1.0 - maskAt(uv + dir * t * W * px)) * w; wsum += w;
  }
  return acc / wsum;
}

void mainImage(out vec4 fragColor, in vec2 fragCoord){
  vec2 uv = fragCoord / iResolution.xy;
  vec3 base = texture(iChannel0, uv).rgb;
  float m0 = maskAt(uv);
  float pump = 1.0 + audioPush * uAudio;
  float W = width * (iResolution.y / 1080.0) * (0.8 + 0.4 * pump);
  float a = angle + spin * iTime;
  vec2 L = vec2(cos(a), sin(a));
  float key  = rimToward(uv, L, W);
  float back = rimToward(uv, -L, W * 0.8);
  // lit edge inside the subject, soft spill just outside it
  vec2 px = 1.0 / iResolution.xy;
  float spill = 0.0;
  for (int i = 0; i < 12; i++){
    float fi = float(i) + 0.5, d = sqrt(fi / 12.0), an = fi * 2.39996;
    spill += maskAt(uv + vec2(cos(an), sin(an)) * d * W * 1.6 * px);
  }
  spill = (spill / 12.0) * (1.0 - m0);
  vec3 lum = vec3(dot(base, vec3(0.299, 0.587, 0.114)));
  vec3 rim = (colorA * key * key + colorB * back * back * 0.7) * m0;
  vec3 col = base + rim * intensity * pump * (0.6 + 0.6 * lum)
           + (colorA * 0.6 + colorB * 0.4) * spill * bloom * intensity * pump * 0.5;
  fragColor = vec4(col, 1.0);
}
