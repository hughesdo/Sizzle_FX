// Glow: single-pass golden-angle bloom over thresholded brights.
uniform float threshold;
uniform float radius;
uniform float strength;
uniform float audioPush;
uniform vec3  tint;

vec3 bright(vec2 u){ vec3 c = texture(iChannel0, u).rgb; float l = max(c.r, max(c.g, c.b)); return c * smoothstep(threshold, threshold + 0.2, l); }

void mainImage(out vec4 fragColor, in vec2 fragCoord){
  vec2 uv = fragCoord / iResolution.xy;
  vec3 base = texture(iChannel0, uv).rgb;
  vec2 r = radius * (iResolution.y / 1080.0) / iResolution.xy;
  vec3 acc = vec3(0.0); float ws = 0.0;
  for (int i = 0; i < 48; i++){
    float fi = float(i) + 0.5;
    float d = sqrt(fi / 48.0);
    float a = fi * 2.39996;
    float w = 1.0 - d * 0.8;
    acc += bright(uv + vec2(cos(a), sin(a)) * d * r) * w; ws += w;
  }
  vec3 bloom = acc / ws * tint * strength * (1.0 + audioPush * uAudio);
  fragColor = vec4(base + bloom, 1.0);
}
