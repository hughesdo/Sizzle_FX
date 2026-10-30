// Spotlight: grey, dark background; light pool centred on the subject.
uniform float desat;
uniform float darken;
uniform float pool;
uniform float poolSize;
uniform float boost;
uniform float audioPush;

void mainImage(out vec4 fragColor, in vec2 fragCoord){
  vec2 uv = fragCoord / iResolution.xy;
  vec3 base = texture(iChannel0, uv).rgb;
  float m0 = maskAt(uv);
  vec3 grey = vec3(dot(base, vec3(0.2126, 0.7152, 0.0722)));
  vec2 p = (uv - uMaskCentroid) * vec2(iResolution.x / iResolution.y, 1.0);
  float size = poolSize * (1.0 + audioPush * uAudio * 0.3);
  float light = mix(1.0, smoothstep(size, size * 0.2, length(p)) * 1.2 + 0.15, pool);
  vec3 bg = mix(base, grey, desat) * (1.0 - darken) * light;
  vec3 fg = base * boost;
  fragColor = vec4(mix(bg, fg, m0), 1.0);
}
