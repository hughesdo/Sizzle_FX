// RGB Split Clone: three single-channel copies of the subject, offset along a direction.
uniform float amount;
uniform float audioPush;
uniform float angle;
uniform float spin;
uniform float opacity;
uniform float front;

float inside(vec2 u){ return step(0.0, u.x) * step(u.x, 1.0) * step(0.0, u.y) * step(u.y, 1.0); }

void mainImage(out vec4 fragColor, in vec2 fragCoord){
  vec2 uv = fragCoord / iResolution.xy;
  float aspect = iResolution.x / iResolution.y;
  vec3 base = texture(iChannel0, uv).rgb;
  float m0 = maskAt(uv);
  float a = angle + iTime * spin;
  vec2 d = vec2(cos(a) / aspect, sin(a)) * (amount + audioPush * uAudio);
  vec2 ur = uv - d, ub = uv + d;
  float mr = maskAt(ur) * inside(ur), mg = m0, mb = maskAt(ub) * inside(ub);
  vec3 clone = vec3(texture(iChannel0, ur).r * mr, texture(iChannel0, uv).g * mg, texture(iChannel0, ub).b * mb);
  // keep the background as it is where no clone channel lands; add the split subject
  vec3 bg = base * (1.0 - max(mr, max(mg, mb)) * opacity);
  vec3 outc = bg + clone * opacity * 1.2;
  outc = mix(outc, base, m0 * front);
  fragColor = vec4(outc, 1.0);
}
