// Smear (after Timewarp post.glsl uSmear): one-sided streak, brightest near the source.
uniform float streak;
uniform float audioPush;
uniform float angle;
uniform float rgb;

void mainImage(out vec4 fragColor, in vec2 fragCoord){
  vec2 uv = fragCoord / iResolution.xy;
  float aspect = iResolution.x / iResolution.y;
  vec2 dir = vec2(cos(angle) / aspect, sin(angle)) * (streak + audioPush * uAudio);
  vec3 acc = vec3(0.0); float ws = 0.0;
  for (int i = 0; i < 24; i++){
    float f = float(i) / 23.0;
    float w = 1.0 - f * 0.7;
    vec2 u = uv + dir * f;
    vec3 c = vec3(texture(iChannel0, u + dir * f * rgb * 0.15).r, texture(iChannel0, u).g, texture(iChannel0, u - dir * f * rgb * 0.15).b);
    acc += c * w; ws += w;
  }
  fragColor = vec4(acc / ws, 1.0);
}
