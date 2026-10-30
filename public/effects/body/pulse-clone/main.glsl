// Pulse Clone: copies of the subject scaled about its centroid, behind it.
uniform int   copies;
uniform float scale;
uniform float audioPush;
uniform float opacity;
uniform vec3  tint;

float inside(vec2 u){ return step(0.0, u.x) * step(u.x, 1.0) * step(0.0, u.y) * step(u.y, 1.0); }

void mainImage(out vec4 fragColor, in vec2 fragCoord){
  vec2 uv = fragCoord / iResolution.xy;
  vec3 base = texture(iChannel0, uv).rgb;
  float m0 = maskAt(uv);
  vec2 c = uMaskCentroid;
  float step1 = scale + audioPush * uAudio;
  vec3 acc = vec3(0.0);
  for (int i = 1; i <= 8; i++){
    if (i > copies) break;
    float k = 1.0 + step1 * float(i);
    vec2 su = c + (uv - c) / k;
    float m = maskAt(su) * inside(su);
    float fade = 1.0 - float(i - 1) / float(copies);
    acc += texture(iChannel0, su).rgb * tint * m * fade * opacity;
  }
  vec3 col = base + acc * (1.0 - m0);
  fragColor = vec4(col, 1.0);
}
