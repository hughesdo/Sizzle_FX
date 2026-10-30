// Halation: blurred highlights minus the highlights themselves (an outward ring), tinted red.
uniform float threshold;
uniform float radius;
uniform float strength;
uniform vec3  tint;
uniform float audioPush;

float hi(vec2 u){ vec3 c = texture(iChannel0, u).rgb; return smoothstep(threshold, threshold + 0.15, max(c.r, max(c.g, c.b))); }

void mainImage(out vec4 fragColor, in vec2 fragCoord){
  vec2 uv = fragCoord / iResolution.xy;
  vec3 base = texture(iChannel0, uv).rgb;
  vec2 r = radius * (iResolution.y / 1080.0) / iResolution.xy;
  float acc = 0.0;
  for (int i = 0; i < 32; i++){
    float fi = float(i) + 0.5;
    float d = sqrt(fi / 32.0);
    acc += hi(uv + vec2(cos(fi * 2.39996), sin(fi * 2.39996)) * d * r);
  }
  float halo = max(acc / 32.0 - hi(uv) * 0.6, 0.0);
  fragColor = vec4(base + tint * halo * strength * (1.0 + audioPush * uAudio), 1.0);
}
