// RGB Time Offset: each colour channel from a different moment.
uniform int   delay;
uniform float audioPush;
uniform int   order;

void mainImage(out vec4 fragColor, in vec2 fragCoord){
  vec2 uv = fragCoord / iResolution.xy;
  int d = delay + int(floor(audioPush * uAudio * 4.0 + 0.5));
  vec3 now = texture(iChannel0, uv).rgb;
  // historyTap(.., 0) is the untouched source; keep the chain's own result for "now"
  float g = historyTap(uv, d).g;
  float late = order == 0 ? historyTap(uv, d * 2).b : historyTap(uv, d * 2).r;
  fragColor = order == 0 ? vec4(now.r, g, late, 1.0) : vec4(late, g, now.b, 1.0);
}
