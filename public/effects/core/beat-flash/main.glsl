// Beat Flash (after Timewarp post.glsl flash / wash / invert)
uniform int   mode;
uniform float amount;
uniform float threshold;

void mainImage(out vec4 fragColor, in vec2 fragCoord){
  vec2 uv = fragCoord / iResolution.xy;
  vec3 col = texture(iChannel0, uv).rgb;
  float k = clamp((uAudio - threshold) / max(1e-3, 1.0 - threshold), 0.0, 1.0) * amount;
  if (mode == 0) col += vec3(k);
  else if (mode == 1) col = mix(col, vec3(0.86, 0.86, 0.88) + col * 0.25, clamp(k, 0.0, 1.0));
  else if (mode == 2) col = mix(col, vec3(1.0) - clamp(col, 0.0, 1.0) * vec3(0.95, 0.93, 0.9), clamp(k, 0.0, 1.0));
  else col *= 1.0 + 2.0 * k;
  fragColor = vec4(col, 1.0);
}
