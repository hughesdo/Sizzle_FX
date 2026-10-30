// Rotational Clone: segment the subject, make N copies of the matte, rotate each a
// few degrees around the subject's centre, offset slightly, blend additively with
// transparency, then put the real subject back on top.
uniform int   copies;
uniform float spread;
uniform float offset;
uniform float opacity;
uniform int   blend;
uniform int   tint;
uniform vec3  color;
uniform float front;
uniform float audioPush;
uniform float sway;

vec3 hue(float h){ return clamp(abs(fract(h + vec3(0.0, 2.0, 1.0) / 3.0) * 6.0 - 3.0) - 1.0, 0.0, 1.0); }
float inside(vec2 u){ return step(0.0, u.x) * step(u.x, 1.0) * step(0.0, u.y) * step(u.y, 1.0); }

void mainImage(out vec4 fragColor, in vec2 fragCoord){
  vec2 uv = fragCoord / iResolution.xy;
  vec2 asp = vec2(iResolution.x / iResolution.y, 1.0);
  vec3 base = texture(iChannel0, uv).rgb;
  float m0 = maskAt(uv);
  vec2 c = uMaskCentroid;
  float amp = 1.0 + audioPush * uAudio;
  vec3 acc = vec3(0.0);
  vec3 over = base; // for "normal" blend
  for (int i = 0; i < 8; i++){
    if (i >= copies) break;
    float fi = float(i);
    float side = mod(fi, 2.0) < 0.5 ? 1.0 : -1.0;
    float k = (fi + 1.0) / float(copies);                       // 1/n .. 1
    float a = radians(spread) * k * side * amp + sin(iTime * 1.3 + fi * 2.1 + uSeed) * radians(spread) * 0.25 * sway;
    float ph = fi * 2.39996 + uSeed;
    vec2 off = vec2(cos(ph), sin(ph) * 0.35) * offset * k * amp;
    // inverse-rotate the lookup around the subject centre (aspect-correct)
    vec2 q = (uv - c - off) * asp;
    q = mat2(cos(a), sin(a), -sin(a), cos(a)) * q;
    vec2 su = c + q / asp;
    float m = maskAt(su) * inside(su);
    vec3 col = texture(iChannel0, su).rgb;
    if (tint == 1) col *= i % 3 == 0 ? vec3(1.6, 0.25, 0.25) : i % 3 == 1 ? vec3(0.25, 1.6, 0.35) : vec3(0.3, 0.4, 1.7);
    else if (tint == 2) col = mix(col, hue(fi / float(copies) + iTime * 0.05) * (0.4 + dot(col, vec3(0.33))), 0.75);
    else if (tint == 3) col = color * (0.35 + dot(col, vec3(0.5)));
    acc += col * m * opacity;
    over = mix(over, col, clamp(m * opacity, 0.0, 1.0));
  }
  vec3 outc = blend == 0 ? base + acc : blend == 1 ? 1.0 - (1.0 - base) * (1.0 - clamp(acc, 0.0, 1.0)) : over;
  outc = mix(outc, base, m0 * front);
  fragColor = vec4(outc, 1.0);
}
