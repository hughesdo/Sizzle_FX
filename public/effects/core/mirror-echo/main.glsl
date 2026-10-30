// Mirror Echo (after Timewarp post.glsl uEcho): narrower copies, brightest-wins blend.
uniform float amount;
uniform float squeeze;
uniform int   copies;
uniform vec3  tint;
uniform float audioPush;

void mainImage(out vec4 fragColor, in vec2 fragCoord){
  vec2 uv = fragCoord / iResolution.xy;
  vec3 col = texture(iChannel0, uv).rgb;
  vec3 e = vec3(0.0);
  float s = squeeze, w = 0.55;
  for (int i = 0; i < 5; i++){
    if (i >= copies) break;
    vec2 u = vec2(0.5 + (uv.x - 0.5) * s, uv.y);
    e = max(e, texture(iChannel0, u).rgb * w);
    s *= squeeze; w *= 0.65;
  }
  float k = clamp(amount * (1.0 + audioPush * uAudio), 0.0, 1.0);
  fragColor = vec4(mix(col, max(col, e * tint), k), 1.0);
}
