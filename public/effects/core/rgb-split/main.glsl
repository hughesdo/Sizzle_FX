// RGB Split (after Timewarp post.glsl srgRGB)
uniform float amount;
uniform float audioPush;
uniform float radial;
uniform float angle;

void mainImage(out vec4 fragColor, in vec2 fragCoord){
  vec2 uv = fragCoord / iResolution.xy;
  float aspect = iResolution.x / iResolution.y;
  float k = amount + audioPush * uAudio;
  vec2 off;
  if (radial > 0.5){
    vec2 dir = (uv - 0.5) * vec2(aspect, 1.0);
    off = normalize(dir + 1e-5) * k * (0.4 + length(dir));
  } else {
    off = vec2(cos(angle), sin(angle)) * k;
  }
  off.x /= aspect;
  fragColor = vec4(texture(iChannel0, uv + off).r, texture(iChannel0, uv).g, texture(iChannel0, uv - off).b, 1.0);
}
