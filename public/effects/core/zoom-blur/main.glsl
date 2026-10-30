// Zoom Blur Punch (after Timewarp post.glsl zoom loop)
uniform float amount;
uniform float audioPush;
uniform vec2  center;
uniform float rgb;

void mainImage(out vec4 fragColor, in vec2 fragCoord){
  vec2 uv = fragCoord / iResolution.xy;
  float z = clamp(amount + audioPush * uAudio, 0.0, 2.0);
  vec3 acc = vec3(0.0); float wsum = 0.0;
  for (int i = 0; i < 16; i++){
    float fi = float(i) / 15.0;
    vec2 u = center + (uv - center) * (1.0 - z * fi * 0.3);
    vec2 d = (u - center) * rgb * 4.0;
    vec3 c = vec3(texture(iChannel0, u + d).r, texture(iChannel0, u).g, texture(iChannel0, u - d).b);
    float w = 1.0 - fi * 0.6;
    acc += c * w; wsum += w;
  }
  fragColor = vec4(acc / wsum, 1.0);
}
