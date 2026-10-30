// Slit-Scan: delay grows across the frame; adjacent history frames are blended so it's smooth.
// History holds source frames, so for "now" we use the chain input to keep lower lanes visible.
uniform int   direction;
uniform float depth;
uniform float bands;
uniform float audioPush;

void mainImage(out vec4 fragColor, in vec2 fragCoord){
  vec2 uv = fragCoord / iResolution.xy;
  float t;
  if (direction == 0) t = 1.0 - uv.y;
  else if (direction == 1) t = uv.y;
  else if (direction == 2) t = uv.x;
  else if (direction == 3) t = 1.0 - uv.x;
  else t = clamp(length((uv - 0.5) * vec2(iResolution.x / iResolution.y, 1.0)) * 1.4, 0.0, 1.0);
  if (bands > 0.5) t = floor(t * bands) / bands;
  float d = clamp(depth * (1.0 - audioPush + audioPush * uAudio), 0.0, float(HISTORY_DEPTH - 1)) * t;
  int a = int(floor(d));
  float f = d - float(a);
  vec3 c0 = a == 0 ? texture(iChannel0, uv).rgb : historyTap(uv, a).rgb;
  vec3 c1 = historyTap(uv, a + 1).rgb;
  fragColor = vec4(mix(c0, c1, bands > 0.5 ? 0.0 : f), 1.0);
}
