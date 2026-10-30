// Ghost Trails / Image pass: composite the trail buffer over the input.
uniform int mixMode;

void mainImage(out vec4 fragColor, in vec2 fragCoord){
  vec2 uv = fragCoord / iResolution.xy;
  vec3 a = texture(iChannel0, uv).rgb;
  vec3 t = texture(iChannel1, uv).rgb;
  vec3 c = mixMode == 0 ? max(a, t) : mixMode == 1 ? 1.0 - (1.0 - a) * (1.0 - t * 0.85) : a + t * 0.5;
  fragColor = vec4(c, 1.0);
}
