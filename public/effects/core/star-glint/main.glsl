// Star Glint: bright-pass sampled along 2 or 4 directions with a falloff, added back.
uniform float threshold;
uniform float rayLen;
uniform int   points;
uniform float rotation;
uniform float intensity;
uniform vec3  tint;
uniform float audioPush;

vec3 bright(vec2 uv){
  vec3 c = texture(iChannel0, uv).rgb;
  float l = dot(c, vec3(0.299, 0.587, 0.114));
  return c * smoothstep(threshold, threshold + (1.0 - threshold) * 0.6 + 0.02, l);
}

void mainImage(out vec4 fragColor, in vec2 fragCoord){
  vec2 uv = fragCoord / iResolution.xy;
  vec3 base = texture(iChannel0, uv).rgb;
  float pump = 1.0 + audioPush * uAudio;
  float L = rayLen * (iResolution.y / 1080.0) * pump;
  vec2 px = 1.0 / iResolution.xy;
  vec3 acc = vec3(0.0);
  bool cross = points >= 4;                // 4 = two crossed lines (both ways), 2 = one line
  for (int k = 0; k < 4; k++){
    float on = (cross || k < 2) ? 1.0 : 0.0;
    float a = rotation + float(k) * (cross ? 1.5708 : 3.1416);
    vec2 dir = vec2(cos(a), sin(a)) * px;
    for (int i = 1; i <= 24; i++){
      float t = float(i) / 24.0;
      float w = (1.0 - t) * (1.0 - t);
      acc += bright(uv + dir * t * L) * (w * on);
    }
  }
  acc *= 1.0 / 10.0;
  vec3 star = acc * tint * intensity * pump;
  fragColor = vec4(base + star, 1.0);
}
