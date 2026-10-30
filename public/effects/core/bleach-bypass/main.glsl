// Bleach Bypass: overlay the luma back onto the image (classic formulation).
uniform float amount;
uniform float contrast;
uniform vec3  tint;

void mainImage(out vec4 fragColor, in vec2 fragCoord){
  vec2 uv = fragCoord / iResolution.xy;
  vec3 c = texture(iChannel0, uv).rgb;
  float l = dot(c, vec3(0.2126, 0.7152, 0.0722));
  vec3 L = vec3(l);
  vec3 mult = 2.0 * c * L;
  vec3 scr = 1.0 - 2.0 * (1.0 - c) * (1.0 - L);
  vec3 ov = mix(mult, scr, clamp((l - 0.45) * 10.0, 0.0, 1.0));
  ov = clamp((ov - 0.5) * contrast + 0.5, 0.0, 1.0) * tint;
  fragColor = vec4(mix(c, ov, amount), 1.0);
}
