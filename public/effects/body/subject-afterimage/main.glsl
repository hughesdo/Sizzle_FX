// Subject Afterimage: earlier frames of the subject only (history rgb x history mask).
uniform int   count;
uniform int   spacing;
uniform float decay;
uniform vec3  tint;
uniform float tintAmt;
uniform float audioPush;

void mainImage(out vec4 fragColor, in vec2 fragCoord){
  vec2 uv = fragCoord / iResolution.xy;
  vec3 base = texture(iChannel0, uv).rgb;
  vec3 col = base;
  float d = clamp(decay + audioPush * uAudio, 0.0, 0.99);
  for (int i = 15; i >= 1; i--){
    if (i > count) continue;
    vec4 h = historyTap(uv, i * spacing);
    float w = pow(d, float(i));
    vec3 g = mix(h.rgb, h.rgb * tint * 1.6, tintAmt);
    col = mix(col, max(col, g), h.a * w);
  }
  col = mix(col, base, maskAt(uv));
  fragColor = vec4(col, 1.0);
}
