// Lens Flare Burst (after Timewarp post.glsl uFlare)
uniform vec2  position;
uniform float follow;
uniform float strength;
uniform float audioPush;
uniform float hue;

void mainImage(out vec4 fragColor, in vec2 fragCoord){
  vec2 uv = fragCoord / iResolution.xy;
  float aspect = iResolution.x / iResolution.y;
  vec2 p = (uv - 0.5) * vec2(aspect, 1.0);
  vec2 at = follow > 0.5 && uHasMask > 0.5 ? vec2(uMaskCentroid.x, uMaskBBox.w) : position;
  vec2 fc = (at - 0.5) * vec2(aspect, 1.0);
  vec2 q = p - fc;
  float a = strength + audioPush * uAudio;
  vec3 col = texture(iChannel0, uv).rgb;
  vec3 wash = mix(vec3(0.85, 0.04, 0.2), vec3(0.9, 0.1, 0.5), hue);
  col = mix(col, wash + col * 0.3, clamp(a * 0.65 * smoothstep(1.4, 0.1, length(q)), 0.0, 1.0));
  col += vec3(0.5, 1.0, 0.5) * exp(-abs(q.y) * 240.0) * exp(-abs(q.x) * 1.2) * a * 1.4;
  col += vec3(0.8, 1.0, 0.7) * exp(-abs(q.x) * 300.0) * exp(-abs(q.y) * 2.0) * a * 0.9;
  col += vec3(1.0, 0.9, 1.0) * exp(-length(q) * 18.0) * a * 2.0;
  col += vec3(0.9, 0.3, 1.0) * exp(-length((q - vec2(0.25, 0.08)) * vec2(1.0, 3.0)) * 6.0) * a * 0.8;
  fragColor = vec4(col, 1.0);
}
