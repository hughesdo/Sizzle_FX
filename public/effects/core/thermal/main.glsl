// Thermal Camera
uniform int   palette;
uniform float contrast;
uniform float subjectHeat;
uniform float blur;
uniform float audioPush;

vec3 ironbow(float t){
  vec3 c = mix(vec3(0.0, 0.0, 0.05), vec3(0.2, 0.0, 0.45), smoothstep(0.0, 0.25, t));
  c = mix(c, vec3(0.75, 0.05, 0.4), smoothstep(0.2, 0.45, t));
  c = mix(c, vec3(0.98, 0.45, 0.05), smoothstep(0.4, 0.7, t));
  c = mix(c, vec3(1.0, 0.9, 0.35), smoothstep(0.65, 0.88, t));
  return mix(c, vec3(1.0), smoothstep(0.85, 1.0, t));
}
vec3 rainbow(float t){ return clamp(abs(fract(0.7 - t * 0.7 + vec3(0.0, 2.0, 1.0) / 3.0) * 6.0 - 3.0) - 1.0, 0.0, 1.0) * smoothstep(0.0, 0.15, t); }

void mainImage(out vec4 fragColor, in vec2 fragCoord){
  vec2 uv = fragCoord / iResolution.xy;
  vec2 r = blur * (iResolution.y / 1080.0) / iResolution.xy;
  float l = 0.0;
  for (int i = 0; i < 9; i++){
    vec2 o = vec2(float(i % 3) - 1.0, float(i / 3) - 1.0) * r;
    l += dot(texture(iChannel0, uv + o).rgb, vec3(0.299, 0.587, 0.114));
  }
  l /= 9.0;
  float t = clamp((l - 0.5) * contrast + 0.45 + audioPush * uAudio * 0.2, 0.0, 1.0);
  if (uHasMask > 0.5){
    float m = maskAt(uv);
    t = mix(t * mix(1.0, 0.45, subjectHeat), mix(t, 0.7 + 0.3 * t, subjectHeat), m);
  }
  vec3 c = palette == 0 ? ironbow(t) : palette == 1 ? rainbow(t) : vec3(t);
  fragColor = vec4(c, 1.0);
}
