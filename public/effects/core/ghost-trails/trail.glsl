// Ghost Trails / Trail pass: iChannel1 is this pass's own previous frame.
uniform float persist;
uniform float drift;
uniform float swirl;
uniform float audioPush;
uniform float hueShift;

vec3 rotHue(vec3 c, float a){
  const vec3 k = vec3(0.57735);
  float ca = cos(a);
  return c * ca + cross(k, c) * sin(a) + k * dot(k, c) * (1.0 - ca);
}

void mainImage(out vec4 fragColor, in vec2 fragCoord){
  vec2 uv = fragCoord / iResolution.xy;
  vec2 p = uv - 0.5;
  float a = swirl;
  p = mat2(cos(a), -sin(a), sin(a), cos(a)) * p;
  vec2 back = 0.5 + p * (1.0 - drift);
  vec3 prev = iFrame == 0 ? vec3(0.0) : texture(iChannel1, back).rgb;
  prev = rotHue(prev, hueShift * 6.2832);
  float k = clamp(persist + audioPush * uAudio, 0.0, 0.995);
  vec3 cur = texture(iChannel0, uv).rgb;
  fragColor = vec4(max(cur, prev * k), 1.0);
}
