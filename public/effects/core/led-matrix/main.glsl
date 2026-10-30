// LED Wall (after Timewarp post.glsl LED dot matrix). Cell size is specified
// at 1080p and scaled to the output so preview and export look the same.
uniform float cell;
uniform float threshold;
uniform float boost;
uniform float audioPush;

void mainImage(out vec4 fragColor, in vec2 fragCoord){
  float s = iResolution.y / 1080.0;
  vec2 cellPx = vec2(cell, cell * 1.35) * s;
  vec2 g = fragCoord / cellPx;
  vec2 f = fract(g) - 0.5;
  vec2 uv = (floor(g) + 0.5) * cellPx / iResolution.xy;
  vec3 col = texture(iChannel0, uv).rgb;
  float l = dot(col, vec3(0.3, 0.55, 0.15));
  float on = smoothstep(threshold, threshold + 0.12, l);
  float shape = smoothstep(0.32, 0.2, abs(f.x)) * smoothstep(0.48, 0.36, abs(f.y));
  vec3 lit = normalize(col + 1e-4) * boost * (1.0 + audioPush * uAudio) * min(l * 2.2, 1.5) + 0.1;
  fragColor = vec4(lit * on * shape + vec3(0.02) * shape * (1.0 - on), 1.0);
}
